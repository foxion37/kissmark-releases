#!/bin/zsh
set -euo pipefail

# Build a fresh Release macOS app and install it as /Applications/Kissmark.app.
#
# Safety order (nothing touches the installed app until everything below passes):
#   1. build Release with signing disabled
#   2. verify the built app's exact version BEFORE anything is replaced
#   3. stage the copy beside the installed app and verify its signature
#   4. ask the running copy to quit gracefully (never force-kill unsaved work)
#   5. swap it in, keeping the old bundle until the new one is up and stable
#   6. roll back and restore the old bundle on any signature or launch failure
#   7. register only the installed path; retire the paths Raycast could still pick
#
# Limitation (honest): this is a local ad-hoc signed build and reuses the
# reduced-entitlements procedure (sandbox + user-selected files + network
# client). It deliberately does NOT carry the production iCloud/ubiquity
# entitlements, so this build does not provide the built-in iCloud
# Kissmark folder.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${KISSMARK_DERIVED:-$ROOT/DerivedData}"
DEST="/Applications/Kissmark.app"
STAGE="${DEST}.staged.$$"
BACKUP="${DEST}.previous.$$"
ENTITLEMENTS="${TMPDIR:-/tmp}/kissmark-local-entitlements.$$.plist"

EXPECTED_MARKETING="${KISSMARK_EXPECTED_MARKETING:-2.3.1}"
EXPECTED_BUILD="${KISSMARK_EXPECTED_BUILD:-17}"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
INSTALLED_EXECUTABLE="$DEST/Contents/MacOS/Kissmark"

log() { print -r -- "install-macos: $*"; }

fail() {
  print -r -- "install-macos: error: $*" >&2
  exit 1
}

read_version() {
  plutil -extract "$1" raw "$2/Contents/Info.plist" 2>/dev/null
}

# PIDs whose executable is exactly the installed binary. Only `argv[0]` (field 2
# of `args`) is compared, so launch arguments can never match; `comm` cannot be
# used because macOS reports only the basename there ("Kissmark"), which would
# also match a Debug build from DerivedData. `-ww` disables truncation.
running_pids() {
  ps -ww -Ao pid=,args= | awk -v exe="$INSTALLED_EXECUTABLE" '$2 == exe { print $1 }'
}

# Graceful quit of the app whose bundle is exactly $DEST, by NSRunningApplication
# PID. `tell application "Kissmark" to quit` would resolve a name and could hit an
# unrelated copy (a Debug build, an older install); `kill` would skip the
# orderly terminate path that lets the app save.
graceful_quit_installed() {
  KISSMARK_QUIT_TARGET="$DEST" osascript -l JavaScript <<'JXA' >/dev/null 2>&1 || true
ObjC.import("AppKit");
const target = $.NSProcessInfo.processInfo.environment.objectForKey("KISSMARK_QUIT_TARGET").js;
let terminated = 0;
const apps = $.NSWorkspace.sharedWorkspace.runningApplications.js;
for (const app of apps) {
  try {
    if (app.bundleURL.path.js === target) {
      app.terminate;
      terminated += 1;
    }
  } catch (error) {
  }
}
terminated;
JXA
}

cleanup() {
  rm -rf "$STAGE"
  rm -f "$ENTITLEMENTS"
}
trap cleanup EXIT

cd "$ROOT"

# A leftover backup means an earlier run was interrupted mid-swap. Never delete
# it: it may be the only intact copy of the installed app.
stale_backups=("${DEST}".previous.*(N))
if (( ${#stale_backups[@]} > 0 )); then
  fail "found a leftover backup at ${stale_backups[1]}; inspect it, remove it, then re-run"
fi

log "building Release (marketing ${EXPECTED_MARKETING}, build ${EXPECTED_BUILD})"
xcodebuild \
  -project Kissmark.xcodeproj \
  -scheme Kissmark \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED/Build/Products/Release/Kissmark.app"
[[ -d "$APP" ]] || fail "missing built app at $APP"

built_marketing="$(read_version CFBundleShortVersionString "$APP")"
built_build="$(read_version CFBundleVersion "$APP")"
[[ "$built_marketing" == "$EXPECTED_MARKETING" ]] \
  || fail "built marketing version is '$built_marketing', expected '$EXPECTED_MARKETING'"
[[ "$built_build" == "$EXPECTED_BUILD" ]] \
  || fail "built build version is '$built_build', expected '$EXPECTED_BUILD'"
log "verified built version ${built_marketing} (${built_build})"

# Stage beside the installed app so the final swap is a rename on one volume.
rm -rf "$STAGE"
ditto "$APP" "$STAGE"
bash "$ROOT/scripts/bundle-mcp.sh" "$STAGE" -

cat > "$ENTITLEMENTS" <<'EOF'
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
EOF
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$STAGE"
rm -f "$ENTITLEMENTS"

codesign --verify --deep --strict --verbose=2 "$STAGE"
staged_marketing="$(read_version CFBundleShortVersionString "$STAGE")"
[[ "$staged_marketing" == "$EXPECTED_MARKETING" ]] \
  || fail "staged app marketing version is '$staged_marketing'"
log "staged and signed $STAGE"

# Graceful quit only: never force-kill an app that may hold unsaved work, and
# never signal a copy that is not the installed bundle.
if [[ -n "$(running_pids)" ]]; then
  log "asking the installed Kissmark ($DEST) to quit"
  graceful_quit_installed
  for _ in {1..30}; do
    if [[ -z "$(running_pids)" ]]; then break; fi
    sleep 0.5
  done
  if [[ -n "$(running_pids)" ]]; then
    fail "the installed Kissmark is still running; quit it manually (unsaved work is not force-killed) and re-run"
  fi
fi

rollback() {
  print -r -- "install-macos: error: $1" >&2
  if [[ -d "$BACKUP" ]]; then
    rm -rf "$DEST"
    if mv "$BACKUP" "$DEST"; then
      print -r -- "install-macos: restored the previous $DEST" >&2
    else
      print -r -- "install-macos: could not restore $BACKUP; the previous app is still there" >&2
    fi
  fi
  rm -rf "$STAGE"
  if [[ -d "$DEST" ]]; then
    "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
  fi
  exit 1
}

# Reversible replacement: keep the old bundle until the new one launches. Each
# step is checked explicitly so a failed rename still restores the old app.
if [[ -d "$DEST" ]]; then
  if ! mv "$DEST" "$BACKUP"; then
    rollback "could not move the installed app aside"
  fi
fi
if ! mv "$STAGE" "$DEST"; then
  rollback "could not move the staged app into place"
fi

if ! codesign --verify --deep --strict "$DEST" >/dev/null 2>&1; then
  rollback "the installed copy failed signature verification"
fi

log "launching $DEST"
if ! open "$DEST"; then
  rollback "open failed for $DEST"
fi

# Bounded wait for the installed copy to appear and stay up for 2 s.
launched=false
first_seen_tick=0
for tick in {1..60}; do
  if [[ -n "$(running_pids)" ]]; then
    if (( first_seen_tick == 0 )); then
      first_seen_tick=$tick
    fi
    if (( tick - first_seen_tick >= 4 )); then
      launched=true
      break
    fi
  else
    first_seen_tick=0
  fi
  sleep 0.5
done
if [[ "$launched" != true ]]; then
  rollback "the installed copy did not stay running"
fi

# Register the installed app, then retire the paths Raycast/Spotlight could
# otherwise still launch.
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
if [[ -d "$BACKUP" ]]; then
  "$LSREGISTER" -u "$BACKUP" >/dev/null 2>&1 || true
fi
if [[ -d "$APP" ]]; then
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
fi
rm -rf "$BACKUP"
rm -rf "$STAGE"

log "installed $DEST"
print -r -- "install-macos: version $(read_version CFBundleShortVersionString "$DEST") ($(read_version CFBundleVersion "$DEST"))"
