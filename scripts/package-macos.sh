#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

app_path=""
developer_id="${KISSMARK_DEVELOPER_ID_APPLICATION:-}"
notary_profile="${KISSMARK_NOTARY_PROFILE:-}"
output_dir="${KISSMARK_OUTPUT_DIR:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/package-macos.sh --output-dir DIR [options]

Build an ad-hoc signed macOS DMG by default (not notarized). Developer ID and
a notarytool Keychain profile are optional for notarized releases.

Options:
  --app PATH                 Package an existing Kissmark.app instead of building.
  --developer-id IDENTITY    Developer ID Application identity used for signing.
  --notary-profile PROFILE   notarytool Keychain profile used for notarization.
  --output-dir DIR           Required output directory.
  -h, --help                 Show this help.

Environment equivalents:
  KISSMARK_DEVELOPER_ID_APPLICATION
  KISSMARK_NOTARY_PROFILE
  KISSMARK_OUTPUT_DIR
USAGE
}

while (($# > 0)); do
  case "$1" in
    --app)
      app_path="${2:?--app requires a path}"
      shift 2
      ;;
    --developer-id)
      developer_id="${2:?--developer-id requires an identity}"
      shift 2
      ;;
    --notary-profile)
      notary_profile="${2:?--notary-profile requires a profile}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:?--output-dir requires a directory}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$output_dir" ]]; then
  echo "Packaging requires --output-dir or KISSMARK_OUTPUT_DIR." >&2
  exit 2
fi

if [[ -n "$notary_profile" && -z "$developer_id" ]]; then
  echo "Notarization requires --developer-id." >&2
  exit 2
fi

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/kissmark-package.XXXXXX")"

cleanup() {
  case "$temp_root" in
    "${TMPDIR:-/tmp}"/kissmark-package.*)
      /bin/rm -rf -- "$temp_root"
      ;;
  esac
}
trap cleanup EXIT

if [[ -z "$app_path" ]]; then
  if ! git -C "$repo_root" diff --quiet || ! git -C "$repo_root" diff --cached --quiet; then
    echo "Refusing to build from a dirty tracked worktree. Commit or stash tracked changes first." >&2
    exit 1
  fi

  derived_data="$temp_root/DerivedData"
  xcodebuild \
    -project "$repo_root/Kissmark.xcodeproj" \
    -scheme Kissmark \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build
  app_path="$derived_data/Build/Products/Release/Kissmark.app"
fi

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

staging_dir="$temp_root/staging"
staged_app="$staging_dir/Kissmark.app"
mkdir -p "$staging_dir" "$output_dir"
ditto "$app_path" "$staged_app"
ln -s /Applications "$staging_dir/Applications"

# Local installs and DMGs carry identical helper/desktop-extension artifacts.
bash "$script_dir/bundle-mcp.sh" "$staged_app" "${developer_id:--}"

entitlements="$repo_root/Kissmark/Kissmark-macOS.entitlements"
if [[ -n "$developer_id" ]]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$entitlements" \
    --sign "$developer_id" \
    "$staged_app"
  package_kind="developer-id"
else
  # Ad-hoc signatures cannot carry iCloud entitlements (the app would be killed at
  # launch), so a local package keeps only sandbox, user-selected files and the
  # network client WKWebView needs. The built-in iCloud Kissmark folder is off.
  local_entitlements="$temp_root/local.entitlements"
  cat > "$local_entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
PLIST
  codesign \
    --force \
    --options runtime \
    --entitlements "$local_entitlements" \
    --sign - \
    "$staged_app"
  package_kind="adhoc"
fi

codesign --verify --deep --strict --verbose=2 "$staged_app"

version="$(plutil -extract CFBundleShortVersionString raw "$staged_app/Contents/Info.plist")"
commit="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
dmg_name="Kissmark-${version}-${package_kind}-${commit}.dmg"
dmg_path="$output_dir/$dmg_name"

if [[ -e "$dmg_path" ]]; then
  echo "Refusing to overwrite existing package: $dmg_path" >&2
  exit 1
fi

hdiutil create \
  -volname Kissmark \
  -srcfolder "$staging_dir" \
  -format UDZO \
  "$dmg_path"

if [[ -n "$developer_id" ]]; then
  codesign --force --timestamp --sign "$developer_id" "$dmg_path"
  codesign --verify --strict --verbose=2 "$dmg_path"
fi

if [[ -n "$notary_profile" ]]; then
  xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
fi

echo "Created: $dmg_path"
shasum -a 256 "$dmg_path"
