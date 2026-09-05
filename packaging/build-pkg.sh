#!/usr/bin/env bash
# build-pkg.sh — build the TetherCam macOS installer package from a built .plugin bundle.
#
# Produces, in --out:
#   TetherCam-obs-plugin.pkg         signed distribution package (signed only with --sign-identity)
#   TetherCam-obs-plugin.pkg.sha256  checksum, "<sha256>  <filename>" (shasum -c compatible)
#   TetherCam-obs-plugin.zip         ditto archive of the .plugin bundle (fallback install path)
#   TetherCam-obs-plugin.zip.sha256
#
# The package installs into the *installing user's* home:
#   ~/Library/Application Support/obs-studio/plugins/<name>.plugin
# See packaging/distribution.xml.in for why no postinstall script is needed.
#
# This script never installs anything and never touches ~/Library.
#
# Usage:
#   packaging/build-pkg.sh --plugin <path/to/x.plugin> --version 0.1.0 --out /tmp/tethercam-pkg
#                          [--sign-identity "Developer ID Installer: Name (TEAMID)"]
#                          [--identifier at.gotzendorfer.obs-iphone-usb-cam]
#                          [--min-macos 12.0]
set -euo pipefail

PRODUCT_TITLE="TetherCam for OBS"
PRODUCT_DESCRIPTION="Use an iPhone as an OBS camera over the USB cable. Installs the OBS source plugin into your personal OBS plugin folder."
ORGANIZATION="at.gotzendorfer"
ASSET_BASENAME="TetherCam-obs-plugin"
BUNDLE_ID="at.gotzendorfer.obs-iphone-usb-cam"
MIN_MACOS="12.0"

PLUGIN=""
VERSION=""
OUT=""
SIGN_IDENTITY=""

die() { printf 'build-pkg: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --plugin)        PLUGIN="${2:-}"; shift 2 ;;
        --version)       VERSION="${2:-}"; shift 2 ;;
        --out)           OUT="${2:-}"; shift 2 ;;
        --sign-identity) SIGN_IDENTITY="${2:-}"; shift 2 ;;
        --identifier)    BUNDLE_ID="${2:-}"; shift 2 ;;
        --min-macos)     MIN_MACOS="${2:-}"; shift 2 ;;
        -h|--help)       sed -n '2,25p' "$0"; exit 0 ;;
        *)               die "unknown argument: $1" ;;
    esac
done

[ -n "$PLUGIN" ]  || die "--plugin is required"
[ -n "$VERSION" ] || die "--version is required"
[ -n "$OUT" ]     || die "--out is required"
[ -d "$PLUGIN" ]  || die "not a bundle directory: $PLUGIN"

case "$PLUGIN" in
    *.plugin) ;;
    *) die "--plugin must point at a *.plugin bundle, got: $PLUGIN" ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/distribution.xml.in"
[ -f "$TEMPLATE" ] || die "missing $TEMPLATE"

PLUGIN_NAME="$(basename "$PLUGIN")"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
PLUGIN="$(cd "$(dirname "$PLUGIN")" && pwd)/$PLUGIN_NAME"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tethercam-stage.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

PAYLOAD="$STAGE/payload"
COMPONENTS="$STAGE/components"
PLUGIN_DIR="$PAYLOAD/Library/Application Support/obs-studio/plugins"
mkdir -p "$PLUGIN_DIR" "$COMPONENTS"

# ditto preserves the bundle's symlink layout and permissions. --noextattr strips
# com.apple.provenance, the only xattr the build leaves behind, so nothing
# machine-specific travels into the payload. Measured: the BOM still lists a "._name"
# AppleDouble sibling per entry either way -- pkgbuild emits those unconditionally --
# so this is about payload hygiene, not about the file count. The code signature lives
# in the Mach-O and in Contents/_CodeSignature, not in xattrs; the codesign --verify
# below is the check that keeps that claim honest.
ditto --noextattr --norsrc "$PLUGIN" "$PLUGIN_DIR/$PLUGIN_NAME"

echo "== payload"
find "$PAYLOAD" -maxdepth 6 -print | sed "s|^$PAYLOAD|  .|"

echo "== verifying the staged bundle is still validly signed"
codesign --verify --strict "$PLUGIN_DIR/$PLUGIN_NAME" \
    || die "staged bundle fails codesign --verify"

COMPONENT_PKG="${ASSET_BASENAME}-component.pkg"
echo "== pkgbuild"
/usr/bin/pkgbuild \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --root "$PAYLOAD" \
    --install-location "/" \
    "$COMPONENTS/$COMPONENT_PKG"

DIST="$STAGE/distribution.xml"
sed \
    -e "s|@PRODUCT_TITLE@|$PRODUCT_TITLE|g" \
    -e "s|@PRODUCT_DESCRIPTION@|$PRODUCT_DESCRIPTION|g" \
    -e "s|@ORGANIZATION@|$ORGANIZATION|g" \
    -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@COMPONENT_PKG@|$COMPONENT_PKG|g" \
    -e "s|@MIN_MACOS@|$MIN_MACOS|g" \
    "$TEMPLATE" >"$DIST"

PKG="$OUT/${ASSET_BASENAME}.pkg"
echo "== productbuild"
if [ -n "$SIGN_IDENTITY" ]; then
    /usr/bin/productbuild \
        --distribution "$DIST" \
        --package-path "$COMPONENTS" \
        --sign "$SIGN_IDENTITY" \
        "$PKG"
else
    echo "   WARNING: no --sign-identity given; the .pkg is UNSIGNED."
    echo "   An unsigned .pkg cannot be notarized and Gatekeeper will block it."
    echo "   Sign with a 'Developer ID Installer' certificate for public releases."
    /usr/bin/productbuild \
        --distribution "$DIST" \
        --package-path "$COMPONENTS" \
        "$PKG"
fi

ZIP="$OUT/${ASSET_BASENAME}.zip"
echo "== zip (fallback install path, carries the Developer ID Application signature)"
rm -f "$ZIP"
ditto -c -k --keepParent --sequesterRsrc "$PLUGIN" "$ZIP"

echo "== checksums"
for f in "$PKG" "$ZIP"; do
    ( cd "$(dirname "$f")" && shasum -a 256 "$(basename "$f")" >"$(basename "$f").sha256" )
    cat "$f.sha256"
done

echo
echo "PASS  $PKG"
