#!/usr/bin/env bash
# install.sh — install the TetherCam OBS plugin from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/Kanevry/tethercam/main/scripts/install.sh | bash
#
# Two install paths:
#   pkg  (default) hands the signed+notarized installer to /usr/sbin/installer,
#        target CurrentUserHomeDirectory. Nothing is written outside your home.
#   zip  unpacks the .plugin bundle straight into
#        ~/Library/Application Support/obs-studio/plugins/.
#
# Both verify the SHA-256 against the .sha256 asset published next to the archive.
# Options: --zip, --pkg, --version vX.Y.Z, --keep (do not delete the download).
set -euo pipefail

OWNER="goetzendorfer"
REPO="tethercam"
ASSET_BASENAME="TetherCam-obs-plugin"
PLUGIN_DIR="$HOME/Library/Application Support/obs-studio/plugins"

MODE="pkg"
VERSION="latest"
KEEP=0

info() { printf '\033[1m==\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --zip)     MODE="zip"; shift ;;
        --pkg)     MODE="pkg"; shift ;;
        --version) VERSION="${2:-}"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
done

# Running the installer as root would drop the plugin into root's home, where OBS
# never looks, and would leave root-owned files in a user directory if it did not.
[ "$(id -u)" -ne 0 ] || die "do not run this as root (no sudo). The plugin installs into your own home directory."

[ "$(uname -s)" = "Darwin" ] || die "TetherCam is macOS-only."

command -v curl >/dev/null || die "curl not found"
command -v shasum >/dev/null || die "shasum not found"

case "$VERSION" in
    latest) BASE_URL="https://github.com/$OWNER/$REPO/releases/latest/download" ;;
    *)      BASE_URL="https://github.com/$OWNER/$REPO/releases/download/$VERSION" ;;
esac

case "$MODE" in
    pkg) ASSET="$ASSET_BASENAME.pkg" ;;
    zip) ASSET="$ASSET_BASENAME.zip" ;;
esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tethercam-install.XXXXXX")"
cleanup() { [ "$KEEP" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT

info "downloading $ASSET ($VERSION)"
curl -fsSL --proto '=https' --tlsv1.2 -o "$WORK/$ASSET" "$BASE_URL/$ASSET" \
    || die "download failed: $BASE_URL/$ASSET"
curl -fsSL --proto '=https' --tlsv1.2 -o "$WORK/$ASSET.sha256" "$BASE_URL/$ASSET.sha256" \
    || die "checksum asset missing: $BASE_URL/$ASSET.sha256 — refusing to install unverified"

info "verifying sha256"
# The .sha256 asset is "<hash>  <filename>"; compare the hash field only, because the
# recorded filename is relative to the build machine's output directory.
EXPECTED="$(awk 'NR==1 {print $1}' "$WORK/$ASSET.sha256")"
ACTUAL="$(shasum -a 256 "$WORK/$ASSET" | awk '{print $1}')"
[ -n "$EXPECTED" ] || die "could not read expected hash"
[ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch — expected $EXPECTED, got $ACTUAL. Not installing."
echo "   ok  $ACTUAL"

if [ "$MODE" = "pkg" ]; then
    info "installing into $PLUGIN_DIR"
    /usr/sbin/installer -pkg "$WORK/$ASSET" -target CurrentUserHomeDirectory \
        || die "installer failed. Retry with --zip, or open the .pkg in Finder to read the error."
else
    command -v ditto >/dev/null || die "ditto not found"
    info "unpacking into $PLUGIN_DIR"
    mkdir -p "$PLUGIN_DIR"
    ditto -x -k "$WORK/$ASSET" "$WORK/unpacked" || die "unzip failed"
    BUNDLE="$(find "$WORK/unpacked" -maxdepth 2 -name '*.plugin' -print -quit)"
    [ -n "$BUNDLE" ] || die "no .plugin bundle inside $ASSET"
    NAME="$(basename "$BUNDLE")"
    # Replace rather than merge: a leftover file from an older version inside the
    # bundle would invalidate the code signature and OBS would refuse to load it.
    rm -rf "${PLUGIN_DIR:?}/${NAME:?}"
    ditto "$BUNDLE" "$PLUGIN_DIR/$NAME"
    # Downloaded archives carry com.apple.quarantine; left in place, Gatekeeper
    # blocks the dylib load inside OBS with no visible error.
    xattr -dr com.apple.quarantine "$PLUGIN_DIR/$NAME" 2>/dev/null || true
    codesign --verify --strict "$PLUGIN_DIR/$NAME" \
        || warn "the installed bundle does not pass codesign --verify; OBS may refuse to load it"
fi

info "done"
echo
echo "  Restart OBS. The source is called 'iPhone USB Camera'."
echo "  Connect the iPhone by cable, open the TetherCam app, then add the source in OBS."
