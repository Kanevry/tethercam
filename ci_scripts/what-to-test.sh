#!/usr/bin/env bash
# what-to-test.sh: write the TestFlight "What to Test" text for a release tag.
#
#   ci_scripts/what-to-test.sh --out-dir <dir>
#
# Contract variable read: CI_TAG (the release tag, required).
#
# Works on the git repository of the current directory and never touches the
# network. Writes <dir>/WhatToTest.en-US.txt and <dir>/WhatToTest.de-DE.txt with
# the same text. Source, first hit wins:
#   1. the body of the annotated tag (scripts/release.sh puts the CHANGELOG
#      section there), markdown emphasis and code marks removed;
#   2. feat/fix/perf commit subjects since the previous v* tag, without the
#      web, ci, scripts and release scopes.
# Exit: 0 written, 1 no usable text, 2 usage or unknown tag, 3 shallow clone.
set -euo pipefail

export PYTHONIOENCODING=utf-8

die() {
    local code="$1"
    shift
    echo "what-to-test.sh: $*" >&2
    exit "$code"
}

usage() {
    die 2 "usage: CI_TAG=<tag> ci_scripts/what-to-test.sh --out-dir <dir>"
}

# argv[1]: annotation | commits. Reads raw text on stdin, writes the cleaned lines.
# Blank-line runs collapse to one; leading and trailing blank lines are dropped.
CLEAN_PY='
import re, sys
mode = sys.argv[1]
raw = sys.stdin.read()
if mode == "annotation":
    lines = [l.rstrip() for l in raw.replace("**", "").replace("`", "").split("\n")]
else:
    head = re.compile(r"(feat|fix|perf)(?:\(([^)]*)\))?!?: (.+)")
    refs = re.compile(r"\s*\(#\d+(?:,\s*#\d+)*\)\s*\Z")
    skip = {"web", "ci", "scripts", "release"}
    lines = []
    for subject in raw.split("\n"):
        m = head.match(subject)
        if not m:
            continue
        scopes = {s.strip().lower() for s in (m.group(2) or "").split(",")}
        if scopes & skip:
            continue
        text = refs.sub("", m.group(3)).strip()
        if text:
            lines.append("- " + text)
out = []
for l in lines:
    if l or (out and out[-1]):
        out.append(l)
while out and not out[-1]:
    out.pop()
sys.stdout.write("\n".join(out))
'

# argv[1]: limit in characters. Cuts at the last line boundary within the limit.
TRUNCATE_PY='
import sys
limit = int(sys.argv[1])
text = sys.stdin.read().rstrip("\n")
if len(text) > limit:
    cut = text[:limit]
    if text[limit] != "\n":
        nl = cut.rfind("\n")
        # A single line longer than the cap is cut mid-line rather than to nothing.
        cut = cut[:nl] if nl > 0 else cut
    text = cut.rstrip()
    sys.stderr.write("what-to-test.sh: text cut to %d characters at a line boundary\n" % len(text))
sys.stdout.write(text)
'

out_dir=""
tag="${CI_TAG:-}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --out-dir) [ "$#" -ge 2 ] || usage; out_dir="$2"; shift 2 ;;
        *)         usage ;;
    esac
done
[ -n "$out_dir" ] && [ -n "$tag" ] || usage

# Apple's documentation states no maximum length for whatsNew; 4000 is a
# conservative cap of our own, not a documented limit.
max=4000

for tool in git python3; do
    command -v "$tool" >/dev/null 2>&1 || die 2 "$tool not found"
done

en_file="$out_dir/WhatToTest.en-US.txt"
de_file="$out_dir/WhatToTest.de-DE.txt"
# A failed run leaves no text behind that a later step could upload, neither a
# partial file of this run nor a stale one of an earlier run.
on_exit() {
    local rc=$?
    # Under set -e a failing rm here would replace the exit code.
    if [ "$rc" -ne 0 ]; then
        rm -f "$en_file" "$de_file" || true
    fi
    exit "$rc"
}
trap on_exit EXIT

git rev-parse --git-dir >/dev/null 2>&1 || die 2 "not inside a git repository"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die 2 "unknown tag '$tag'"

text=""
source_name=""
if [ "$(git cat-file -t "refs/tags/$tag")" = tag ]; then
    text="$(git tag -l --format='%(contents:body)' "$tag" | python3 -c "$CLEAN_PY" annotation)"
    source_name="annotation of tag $tag"
fi

if [ -z "$text" ]; then
    # Without full history the range below is silently cut short.
    if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
        die 3 "shallow clone: the commit fallback for $tag needs full history (actions/checkout: fetch-depth: 0)"
    fi
    prev="$(git describe --tags --abbrev=0 --match 'v*' "refs/tags/$tag^" 2>/dev/null || true)"
    if [ -n "$prev" ]; then
        range="refs/tags/$prev..refs/tags/$tag"
    else
        range="refs/tags/$tag"
    fi
    text="$(git log --no-merges --format=%s "$range" | python3 -c "$CLEAN_PY" commits)"
    source_name="feat/fix/perf commit subjects in $range"
fi

text="$(printf '%s\n' "$text" | python3 -c "$TRUNCATE_PY" "$max")"
[ -n "$text" ] || die 1 "no What to Test text for $tag: nothing usable in the $source_name (a commit counts only as feat/fix/perf outside the web, ci, scripts and release scopes)"

mkdir -p "$out_dir"
printf '%s\n' "$text" >"$en_file"
cp "$en_file" "$de_file"
echo "what-to-test.sh: wrote $en_file and $de_file from the $source_name" >&2
cat "$en_file"
