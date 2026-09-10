#!/usr/bin/env bash
# mac-app-release.sh: builds the macOS TetherCam app (menu bar host + Camera
# Extension) as a Developer ID signed, notarized, stapled .dmg and optionally
# uploads it to a GitHub release of Kanevry/tethercam.
#
#   scripts/mac-app-release.sh                 # archive, export, dmg, notarize, staple
#   scripts/mac-app-release.sh --upload v0.2.0 # ... and attach to that release
#   scripts/mac-app-release.sh --skip-notarize # local smoke test of the packaging
#
# Needs: xcodegen, Xcode, a "Developer ID Application" identity in the login
# keychain, and the notarization key from .env.local (ASC_KEY_ID, ASC_ISSUER_ID,
# ASC_KEY_PATH; the same key the iOS upload uses). Never prints key material.
# Output: dist/TetherCam-mac.dmg (+ .sha256); logs in build/mac-app-release-*.log.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/mac-app"
DIST="$ROOT/dist"
BUILD="$ROOT/build/mac-app-release"
LOG="$ROOT/build/mac-app-release-$(date +%Y%m%d-%H%M%S).log"
ASSET="TetherCam-mac"
VOLNAME="TetherCam"
UPLOAD_TAG=""
NOTARIZE=1

while [ $# -gt 0 ]; do
    case "$1" in
        --upload) UPLOAD_TAG="$2"; shift 2 ;;
        --skip-notarize) NOTARIZE=0; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$DIST" "$ROOT/build"
say() { printf '\n== %s\n' "$*" | tee -a "$LOG"; }
die() { echo "FAIL: $*" >&2; echo "log: $LOG" >&2; exit 1; }

# --- signing identity and notarization key ---------------------------------
IDENT="$(security find-identity -v -p codesigning \
         | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
[ -n "$IDENT" ] || die "no 'Developer ID Application' identity in the keychain"
if [ "$NOTARIZE" = 1 ]; then
    # shellcheck disable=SC1091
    [ -f "$ROOT/.env.local" ] && set -a && . "$ROOT/.env.local" && set +a
    : "${ASC_KEY_ID:?ASC_KEY_ID missing (.env.local)}"
    : "${ASC_ISSUER_ID:?ASC_ISSUER_ID missing (.env.local)}"
    KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
    [ -f "$KEY_PATH" ] || die "notarization key not found at $KEY_PATH"
fi

# --- archive + export (Developer ID) ----------------------------------------
say "xcodegen"
(cd "$APP_DIR" && xcodegen generate >>"$LOG" 2>&1) || die "xcodegen (see log)"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' "$APP_DIR/project.yml")"
BUILDNO="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' "$APP_DIR/project.yml")"
say "archive TetherCam $VERSION ($BUILDNO)"
rm -rf "$BUILD"
xcodebuild -project "$APP_DIR/TetherCam.xcodeproj" -scheme TetherCam -configuration Release \
    -archivePath "$BUILD/TetherCam.xcarchive" -derivedDataPath "$BUILD/DerivedData" \
    -allowProvisioningUpdates archive >>"$LOG" 2>&1 || die "xcodebuild archive (see log)"

say "export (method developer-id)"
cat >"$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>G3QZ66475M</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$BUILD/TetherCam.xcarchive" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" -exportPath "$BUILD/export" \
    -allowProvisioningUpdates >>"$LOG" 2>&1 || die "xcodebuild -exportArchive (see log)"
APP="$BUILD/export/TetherCam.app"
[ -d "$APP" ] || die "export produced no TetherCam.app"

say "codesign verification"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tee -a "$LOG" | tail -n 2
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=Developer ID Application" | head -1 | tee -a "$LOG" \
    || die "host is not signed with Developer ID"
codesign -dvv "$APP/Contents/Library/SystemExtensions/at.gotzendorfer.tethercam.mac.camera.systemextension" 2>&1 \
    | grep -E "^Authority=Developer ID Application" | head -1 | tee -a "$LOG" \
    || die "extension is not signed with Developer ID"

# --- dmg --------------------------------------------------------------------
# Layout: 640x400 window, TetherCam.app on the left, the /Applications alias on
# the right, a generated background with an arrow between them. The background is
# drawn at build time (Pillow) so no binary asset lives in the repo. Finder
# scripting is fragile on a headless/locked machine, so every positioning step is
# best-effort: a failure warns and the plain .dmg still ships.
say "dmg"
STAGE="$BUILD/dmg-root"
rm -rf "$STAGE" "$DIST/$ASSET.dmg" "$DIST/$ASSET.dmg.sha256"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/TetherCam.app"
ln -s /Applications "$STAGE/Applications"

if python3 "$ROOT/mac-app/scripts/make-dmg-background.py" "$STAGE/.background/background.png" >>"$LOG" 2>&1; then
    BACKGROUND_OK=1
else
    BACKGROUND_OK=0
    echo "WARN: could not generate the DMG background (Pillow missing?), shipping a plain volume" | tee -a "$LOG"
fi

if [ "$BACKGROUND_OK" = 1 ]; then
    RW="$BUILD/rw.dmg"
    rm -f "$RW"
    hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >>"$LOG" 2>&1 \
        || die "hdiutil create (read-write)"
    MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -Eo '/Volumes/.*$' | head -1)"
    if [ -n "$MOUNT" ]; then
        osascript >>"$LOG" 2>&1 <<APPLESCRIPT || echo "WARN: Finder layout failed, keeping the default view" | tee -a "$LOG"
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 160, 840, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:background.png"
    set position of item "TetherCam.app" of container window to {160, 190}
    set position of item "Applications" of container window to {480, 190}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT
        sync
        hdiutil detach "$MOUNT" >>"$LOG" 2>&1 || hdiutil detach "$MOUNT" -force >>"$LOG" 2>&1 || true
    else
        echo "WARN: could not mount the read-write image, keeping the default view" | tee -a "$LOG"
    fi
    hdiutil convert "$RW" -format UDZO -ov -o "$DIST/$ASSET.dmg" >>"$LOG" 2>&1 || die "hdiutil convert"
else
    hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$ASSET.dmg" >>"$LOG" 2>&1 \
        || die "hdiutil create"
fi
codesign --sign "$IDENT" --timestamp "$DIST/$ASSET.dmg" >>"$LOG" 2>&1 || die "codesign dmg"

# --- notarize + staple --------------------------------------------------------
if [ "$NOTARIZE" = 1 ]; then
    say "notarize (notarytool --wait)"
    xcrun notarytool submit "$DIST/$ASSET.dmg" --key "$KEY_PATH" --key-id "$ASC_KEY_ID" \
        --issuer "$ASC_ISSUER_ID" --wait --timeout 30m 2>&1 | tee -a "$LOG" | grep -E "status:|id:" | tail -n 3
    grep -q "status: Accepted" "$LOG" || die "notarization not accepted (xcrun notarytool log <id> --key ...)"
    say "staple"
    xcrun stapler staple "$DIST/$ASSET.dmg" >>"$LOG" 2>&1 || die "stapler dmg"
    spctl -a -t open --context context:primary-signature -vv "$DIST/$ASSET.dmg" 2>&1 | tee -a "$LOG" | tail -n 2
fi

(cd "$DIST" && shasum -a 256 "$ASSET.dmg" >"$ASSET.dmg.sha256")
say "artefact"
ls -la "$DIST/$ASSET.dmg"; cat "$DIST/$ASSET.dmg.sha256"

# --- upload -------------------------------------------------------------------
if [ -n "$UPLOAD_TAG" ]; then
    say "upload to Kanevry/tethercam release $UPLOAD_TAG"
    gh release upload "$UPLOAD_TAG" "$DIST/$ASSET.dmg" "$DIST/$ASSET.dmg.sha256" \
        --repo Kanevry/tethercam --clobber
    curl -sI "https://github.com/Kanevry/tethercam/releases/latest/download/$ASSET.dmg" | head -1
fi
echo "DONE $VERSION ($BUILDNO) log=$LOG"
