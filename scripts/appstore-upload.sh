#!/usr/bin/env bash
# appstore-upload.sh: local equivalent of .github/workflows/testflight-ios.yml.
#
# Archives the iOS app with automatic signing (the App Store Connect API key lets
# xcodebuild create/refresh the App Store distribution profile on demand) and then
# either uploads it to TestFlight or, with --dry-run, exports a local .ipa so the
# whole signing chain can be validated without touching App Store Connect.
#
#   scripts/appstore-upload.sh --dry-run                 export only, no upload
#   scripts/appstore-upload.sh                           archive + upload to TestFlight
#   scripts/appstore-upload.sh --version 0.1.1 --build-number 7
#
# Credentials: only the .p8 path is sensitive, and it stays OUTSIDE the repository
# (default ~/.appstoreconnect/private_keys/). The key id and the issuer id are
# identifiers, not secrets, so they are defaulted here and can be overridden by the
# environment or by a git-ignored .env.local in the repo root:
#
#   ASC_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
#
# The script never prints the key, and never `cat`s the .p8.
set -euo pipefail

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1m==\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="TetherCam"
TEAM_ID="G3QZ66475M"
PROJECT_YML="ios-app/project.yml"
EXPORT_OPTIONS="packaging/ExportOptions.plist"

DRY_RUN=0
VERSION_OVERRIDE=""
BUILD_OVERRIDE=""

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      DRY_RUN=1; shift ;;
        --version)      VERSION_OVERRIDE="${2:-}"; [ -n "$VERSION_OVERRIDE" ] || die "--version needs X.Y.Z"; shift 2 ;;
        --build-number) BUILD_OVERRIDE="${2:-}";   [ -n "$BUILD_OVERRIDE" ]   || die "--build-number needs N"; shift 2 ;;
        -h|--help)      usage 0 ;;
        *)              die "unknown argument: $1 (try --help)" ;;
    esac
done

# --- credentials -----------------------------------------------------------

# .env.local is git-ignored (.gitignore: .env.*) and may carry ASC_* overrides.
if [ -f "$ROOT/.env.local" ]; then
    info "loading $ROOT/.env.local"
    set -a
    # shellcheck source=/dev/null
    . "$ROOT/.env.local"
    set +a
fi

[ -n "${ASC_KEY_ID:-}" ] || die "ASC_KEY_ID is not set (env or .env.local). See docs/SECRETS.md."
[ -n "${ASC_ISSUER_ID:-}" ] || die "ASC_ISSUER_ID is not set (env or .env.local). See docs/SECRETS.md."
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

[ -f "$ASC_KEY_PATH" ] || die "App Store Connect key not found at $ASC_KEY_PATH
Set ASC_KEY_PATH (env or .env.local) to the AuthKey_<KEYID>.p8 you downloaded.
See docs/SECRETS.md. Never move the key into this repository."

# --- versions --------------------------------------------------------------

yaml_value() { sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"]+)\"?[[:space:]]*$/\1/p" "$PROJECT_YML" | head -1; }

[ -f "$PROJECT_YML" ] || die "missing $PROJECT_YML"
VERSION="${VERSION_OVERRIDE:-$(yaml_value MARKETING_VERSION)}"
BUILD="${BUILD_OVERRIDE:-$(yaml_value CURRENT_PROJECT_VERSION)}"
BUNDLE_ID="$(yaml_value PRODUCT_BUNDLE_IDENTIFIER)"
[ -n "$VERSION" ] || die "could not read MARKETING_VERSION from $PROJECT_YML"
[ -n "$BUILD" ]   || die "could not read CURRENT_PROJECT_VERSION from $PROJECT_YML"

# --- paths -----------------------------------------------------------------

STAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_DIR="$ROOT/build"                       # git-ignored (.gitignore: build/)
ARCHIVE="$BUILD_DIR/TetherCam-$VERSION-$BUILD.xcarchive"
EXPORT_DIR="$BUILD_DIR/appstore-export-$STAMP"
ARCHIVE_LOG="$BUILD_DIR/appstore-archive-$STAMP.log"
EXPORT_LOG="$BUILD_DIR/appstore-export-$STAMP.log"
mkdir -p "$BUILD_DIR"

info "TetherCam $VERSION ($BUILD)  bundle=$BUNDLE_ID  team=$TEAM_ID"
info "API key id $ASC_KEY_ID, key file $ASC_KEY_PATH"
if [ "$DRY_RUN" = 1 ]; then info "DRY RUN: export to disk, no App Store Connect upload"; fi

# --- 1. regenerate the Xcode project ---------------------------------------

command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
info "xcodegen generate"
( cd ios-app && xcodegen generate >/dev/null )

# --- 2. archive ------------------------------------------------------------

info "xcodebuild archive -> $ARCHIVE"
info "   full log: $ARCHIVE_LOG"
rm -rf "$ARCHIVE"
set +e
xcodebuild archive \
    -project ios-app/TetherCam.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    >"$ARCHIVE_LOG" 2>&1
ARCHIVE_RC=$?
set -e

if [ "$ARCHIVE_RC" -ne 0 ] || [ ! -d "$ARCHIVE" ]; then
    echo >&2
    grep -E '(^|[[:space:]])error:|Provisioning|No profiles|Signing for' "$ARCHIVE_LOG" | tail -20 >&2 || true
    echo >&2
    die "archive failed (rc=$ARCHIVE_RC). Full log: $ARCHIVE_LOG
If signing failed: the bundle id $BUNDLE_ID must be registered on
developer.apple.com, and its capability set must cover everything the target
declares in ios-app/project.yml."
fi
info "archive ok"

# --- 3. export (and, unless --dry-run, upload) ------------------------------

PLIST="$EXPORT_OPTIONS"
if [ "$DRY_RUN" = 1 ]; then
    # Same options, but destination=export so xcodebuild writes an .ipa instead of
    # handing the build to App Store Connect. Written to a temp copy: the committed
    # plist is the upload one and stays untouched.
    TMPDIR_PLIST="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$TMPDIR_PLIST'" EXIT
    PLIST="$TMPDIR_PLIST/ExportOptions.plist"
    cp "$EXPORT_OPTIONS" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :destination export" "$PLIST" >/dev/null
fi

info "xcodebuild -exportArchive (destination=$( /usr/libexec/PlistBuddy -c 'Print :destination' "$PLIST" ))"
info "   full log: $EXPORT_LOG"
set +e
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$PLIST" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    >"$EXPORT_LOG" 2>&1
EXPORT_RC=$?
set -e

if [ "$EXPORT_RC" -ne 0 ]; then
    echo >&2
    if grep -q "No suitable application records were found" "$EXPORT_LOG"; then
        die "App Store Connect has no app record for $BUNDLE_ID.

The API key can register bundle ids, but it CANNOT create the app record; only a
human with Account Holder / Admin access can, on the website:

  appstoreconnect.apple.com -> Apps -> + -> New App
    Platform:  iOS
    Bundle ID: $BUNDLE_ID
    Name:      must be unique across the entire App Store
    SKU:       any stable internal string, e.g. tethercam

Re-run this script afterwards. Full log: $EXPORT_LOG"
    fi
    grep -E '(^|[[:space:]])error:|Error Domain' "$EXPORT_LOG" | tail -20 >&2 || true
    echo >&2
    die "export failed (rc=$EXPORT_RC). Full log: $EXPORT_LOG"
fi

# --- 4. report -------------------------------------------------------------

APP="$ARCHIVE/Products/Applications/$SCHEME.app"
if [ -d "$APP" ]; then
    info "codesign summary"
    # -dvvv is what surfaces the Authority chain; -dv alone hides it.
    codesign -dvvv "$APP" 2>&1 | grep -E 'Identifier=|Authority=|TeamIdentifier=' || true
else
    warn "no $SCHEME.app inside the archive; skipping codesign summary"
fi

if [ "$DRY_RUN" = 1 ]; then
    IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -print -quit)"
    [ -n "$IPA" ] || die "export reported success but produced no .ipa in $EXPORT_DIR"
    info "dry run complete"
    echo "  ipa:  $IPA"
    echo "  size: $(du -h "$IPA" | cut -f1)"
    echo "  logs: $ARCHIVE_LOG"
    echo "        $EXPORT_LOG"
    echo
    echo "Nothing was uploaded. Re-run without --dry-run to send the build to TestFlight."
else
    info "uploaded to App Store Connect"
    echo "  version: $VERSION ($BUILD)"
    echo "  logs:    $ARCHIVE_LOG"
    echo "           $EXPORT_LOG"
    echo
    echo "Processing takes 5-30 minutes. Internal testers see the build as soon as it"
    echo "finishes; a PUBLIC link needs an external group + one Beta App Review."
    echo "Check: scripts/asc-api.sh apps"
fi
