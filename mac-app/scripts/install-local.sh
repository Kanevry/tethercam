#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# install-local.sh: build TetherCam.app (Release, automatic Apple Development
# signing), copy it to /Applications, launch it once so it submits the Camera
# Extension activation request, then report the systemextensionsctl state.
#
# Usage: bash mac-app/scripts/install-local.sh [--skip-build]
set -euo pipefail

MAC_APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="at.gotzendorfer.tethercam.mac"
EXT_ID="at.gotzendorfer.tethercam.mac.camera"
BUILT="$MAC_APP/build/Build/Products/Release/TetherCam.app"
DEST="/Applications/TetherCam.app"
SETTINGS_URL="x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

say() { printf 'install-local: %s\n' "$*"; }

if [[ "${1:-}" != "--skip-build" ]]; then
  say "building Release"
  (cd "$MAC_APP" && xcodegen generate >/dev/null)
  (cd "$MAC_APP" && xcodebuild -scheme TetherCam -configuration Release \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      -derivedDataPath build build CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=G3QZ66475M \
      -quiet)
fi
[[ -d "$BUILT" ]] || { say "ERROR: $BUILT missing"; exit 1; }

# Replace only an app that is ours; never delete a stranger's bundle.
if [[ -d "$DEST" ]]; then
  existing=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$existing" == "$BUNDLE_ID" ]]; then
    say "removing previous $DEST"
    rm -rf "$DEST" || { say "ERROR: cannot remove $DEST, run: sudo rm -rf $DEST"; exit 1; }
  else
    say "ERROR: $DEST exists with bundle id '$existing', not ours; move it away first"
    exit 1
  fi
fi

if ! cp -R "$BUILT" "$DEST" 2>/dev/null; then
  say "ERROR: copying to /Applications failed (permissions). Run:"
  say "  sudo cp -R \"$BUILT\" \"$DEST\""
  exit 1
fi
say "installed $DEST"

# Launching submits the OSSystemExtension activation request (AppState.start()).
open -a "$DEST"

state=""
for _ in $(seq 1 20); do
  sleep 1
  line=$(systemextensionsctl list 2>/dev/null | grep "$EXT_ID" | tail -1 || true)
  if [[ -n "$line" ]]; then
    state=$(printf '%s' "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')
    [[ "$state" == "activated enabled" ]] && break
    [[ "$state" == "activated waiting for user" ]] && break
  fi
done

say "systemextensionsctl: ${line:-<no TetherCam line>}"
case "$state" in
  "activated enabled")
    say "DONE: the TetherCam camera extension is enabled. Select 'TetherCam' as camera in any app."
    ;;
  "activated waiting for user")
    say "APPROVAL NEEDED: System Settings > General > Login Items & Extensions > Camera Extensions > enable TetherCam"
    say "opening that pane now"
    open "$SETTINGS_URL" || true
    ;;
  "")
    say "ERROR: no activation request seen within 20 s. Recent sysextd log:"
    log show --last 2m --predicate 'subsystem == "com.apple.sysextd"' 2>/dev/null | tail -20 || true
    ;;
  *)
    say "extension state '$state' (see systemextensionsctl list)"
    ;;
esac
exit 0
