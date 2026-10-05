#!/usr/bin/env bash
set -euo pipefail

# Build/sign the same helper and Claude Desktop bundle for local installs and DMGs.
# Usage: bash scripts/bundle-mcp.sh Kissmark.app [signing-identity]
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app="${1:?Provide a built Kissmark.app}"
identity="${2:--}"
[[ -d "$app/Contents" ]] || { echo "Missing app bundle." >&2; exit 1; }
version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "MCP bundle requires a numeric major.minor.patch version." >&2; exit 1; }

swift build -c release --package-path "$repo_root/mcp" --arch arm64 --arch x86_64
helper_bin="$(swift build -c release --package-path "$repo_root/mcp" --arch arm64 --arch x86_64 --show-bin-path)/kissmark-mcp"
mkdir -p "$app/Contents/Helpers" "$app/Contents/Resources"
# Project and third-party notices accompany both local installs and DMGs.
ditto "$repo_root/LICENSE" "$app/Contents/Resources/Kissmark-LICENSE.txt"
ditto "$repo_root/Kissmark/Resources/ThirdPartyNotices.txt" "$app/Contents/Resources/ThirdPartyNotices.txt"
ditto "$repo_root/Kissmark/Resources/Fonts/Jetendard-Upstream-Notices.txt" "$app/Contents/Resources/Jetendard-Upstream-Notices.txt"
ditto "$helper_bin" "$app/Contents/Helpers/kissmark-mcp"
chmod 755 "$app/Contents/Helpers/kissmark-mcp"
sign_args=(--force --options runtime --sign "$identity")
if [[ "$identity" != "-" ]]; then sign_args+=(--timestamp); fi
codesign "${sign_args[@]}" "$app/Contents/Helpers/kissmark-mcp"

bundle_dir="$(mktemp -d "${TMPDIR:-/tmp}/kissmark-mcpb.XXXXXX")"
cleanup() { rm -rf "$bundle_dir"; }
trap cleanup EXIT
mkdir -p "$bundle_dir/server"
ditto "$app/Contents/Helpers/kissmark-mcp" "$bundle_dir/server/kissmark-mcp"
ditto "$repo_root/LICENSE" "$bundle_dir/LICENSE"
cat > "$bundle_dir/manifest.json" <<JSON
{
  "manifest_version": "0.3",
  "name": "kissmark",
  "display_name": "Kissmark",
  "version": "$version",
  "description": "Open and review local Markdown documents in Kissmark.",
  "author": { "name": "Kissmark" },
  "license": "MIT",
  "server": {
    "type": "binary",
    "entry_point": "server/kissmark-mcp",
    "mcp_config": {
      "command": "\${__dirname}/server/kissmark-mcp",
      "args": [],
      "env": { "KISSMARK_CLIENT_ID": "claude-desktop", "KISSMARK_CLIENT_SCOPE": "user" }
    }
  },
  "compatibility": { "platforms": ["darwin"] }
}
JSON
swift -e 'import Foundation; _ = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))' "$bundle_dir/manifest.json"
rm -f "$app/Contents/Resources/kissmark.mcpb"
ditto -c -k "$bundle_dir" "$app/Contents/Resources/kissmark.mcpb"
echo "Bundled signed MCP helper and kissmark.mcpb"
