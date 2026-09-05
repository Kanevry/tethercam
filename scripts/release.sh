#!/usr/bin/env bash
# release.sh: local release helper. Two phases, because a tag must point at the
# commit that already carries the bumped version numbers:
#
#   scripts/release.sh 0.1.0          bump version files + CHANGELOG, then stop
#   <review the diff, commit it yourself>
#   scripts/release.sh 0.1.0 --tag    create the annotated tag vX.Y.Z (does not push)
#
# This script never commits, never stages, and never pushes. It touches exactly
# three files: obs-plugin/buildspec.json, ios-app/project.yml, CHANGELOG.md.
set -euo pipefail

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1m==\033[0m %s\n' "$*"; }

VERSION="${1:-}"
MODE="${2:-bump}"

[ -n "$VERSION" ] || die "usage: scripts/release.sh X.Y.Z [--tag]"
case "$VERSION" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) die "version must be X.Y.Z (no leading v), got: $VERSION" ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILDSPEC="obs-plugin/buildspec.json"
PROJECT_YML="ios-app/project.yml"
CHANGELOG="CHANGELOG.md"
TAG="v$VERSION"

for f in "$BUILDSPEC" "$PROJECT_YML" "$CHANGELOG"; do
    [ -f "$f" ] || die "missing $f"
done

command -v python3 >/dev/null || die "python3 not found"

if [ "$MODE" = "--tag" ]; then
    CURRENT="$(python3 -c 'import json;print(json.load(open("obs-plugin/buildspec.json"))["version"])')"
    [ "$CURRENT" = "$VERSION" ] \
        || die "$BUILDSPEC says $CURRENT, not $VERSION. Run the bump phase first."
    if ! git diff --quiet -- "$BUILDSPEC" "$PROJECT_YML" "$CHANGELOG"; then
        die "version files have uncommitted changes. Commit them first, otherwise the tag points at a commit without the bump."
    fi
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        die "tag $TAG already exists"
    fi
    NOTES="$(python3 scripts/changelog-section.py "$VERSION" 2>/dev/null || true)"
    git tag -a "$TAG" -m "TetherCam $TAG

$NOTES"
    info "created annotated tag $TAG (not pushed)"
    echo
    echo "Next:"
    echo "  git push origin HEAD              # GitLab, primary"
    echo "  git push origin $TAG"
    echo "  git push github HEAD && git push github $TAG   # mirror; the tag push starts the release workflows"
    echo "  gh run watch --repo <owner>/<repo>"
    exit 0
fi

[ "$MODE" = "bump" ] || die "second argument must be --tag or omitted"

info "bumping to $VERSION"

python3 - "$VERSION" <<'PY'
import json, re, subprocess, sys
from datetime import date

version = sys.argv[1]

# 1) obs-plugin/buildspec.json: rewritten with json.dump to keep it valid; the file
#    is 4-space indented and the template reads it with a plain JSON parser.
path = "obs-plugin/buildspec.json"
with open(path) as fh:
    spec = json.load(fh)
old_plugin = spec["version"]
spec["version"] = version
with open(path, "w") as fh:
    json.dump(spec, fh, indent=4)
    fh.write("\n")
print(f"   buildspec.json      {old_plugin} -> {version}")

# 2) ios-app/project.yml: line-level substitution, not a YAML round-trip, so that
#    comments and key order survive untouched. MARKETING_VERSION is the user-visible
#    version; CURRENT_PROJECT_VERSION is the build number, which App Store Connect
#    requires to be strictly increasing per marketing version.
path = "ios-app/project.yml"
text = open(path).read()
old_marketing = re.search(r'MARKETING_VERSION:\s*"([^"]*)"', text)
old_build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]*)"', text)
if not old_marketing or not old_build:
    sys.exit("project.yml: MARKETING_VERSION / CURRENT_PROJECT_VERSION not found")
try:
    next_build = str(int(old_build.group(1)) + 1)
except ValueError:
    sys.exit(f"CURRENT_PROJECT_VERSION is not an integer: {old_build.group(1)!r}")
text = re.sub(r'(MARKETING_VERSION:\s*)"[^"]*"', rf'\g<1>"{version}"', text)
text = re.sub(r'(CURRENT_PROJECT_VERSION:\s*)"[^"]*"', rf'\g<1>"{next_build}"', text)
open(path, "w").write(text)
print(f"   project.yml         MARKETING_VERSION {old_marketing.group(1)} -> {version}, "
      f"CURRENT_PROJECT_VERSION {old_build.group(1)} -> {next_build}")

# 3) CHANGELOG.md: promote Unreleased to a dated release heading and open a fresh
#    empty Unreleased above it.
path = "CHANGELOG.md"
text = open(path).read()
heading = f"## [{version}] - {date.today().isoformat()}"
if heading.split(" - ")[0] in text:
    print(f"   CHANGELOG.md        already has a [{version}] section, left alone")
elif "## [Unreleased]" in text:
    text = text.replace("## [Unreleased]", f"## [Unreleased]\n\n{heading}", 1)
    open(path, "w").write(text)
    print(f"   CHANGELOG.md        Unreleased -> [{version}]")
else:
    sys.exit("CHANGELOG.md has no '## [Unreleased]' heading")
PY

info "review the diff, then commit"
echo
git --no-pager diff --stat -- "$BUILDSPEC" "$PROJECT_YML" "$CHANGELOG"
echo
echo "Next:"
echo "  git diff                       # read it; the CHANGELOG heading placement in particular"
echo "  git add $BUILDSPEC $PROJECT_YML $CHANGELOG"
echo "  git commit -m 'chore(release): $VERSION'"
echo "  scripts/release.sh $VERSION --tag"
