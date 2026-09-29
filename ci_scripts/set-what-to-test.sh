#!/usr/bin/env bash
# set-what-to-test.sh: set the TestFlight "What to Test" text (whatsNew of the
# build's betaBuildLocalizations) on the build that ios-app/project.yml describes.
#
#   ci_scripts/set-what-to-test.sh [--apply] --text-dir <dir>
#
# Reads <dir>/WhatToTest.en-US.txt and <dir>/WhatToTest.de-DE.txt (what-to-test.sh
# writes them). Without --apply it only prints the requests and calls nothing.
# With --apply it sends them through $ASC_API, which reads ASC_KEY_ID,
# ASC_ISSUER_ID and ASC_KEY_PATH. Safe to re-run: the build's localizations are
# listed first, an existing locale is PATCHed, only a missing one is POSTed.
#
# Contract variable read: CI_BUNDLE_ID (required).
# Env: PROJECT_YML (default ios-app/project.yml), ASC_API (default
# scripts/asc-api.sh, one command name), WHAT_TO_TEST_TIMEOUT_S (default 2700),
# WHAT_TO_TEST_POLL_S (default 30).
set -euo pipefail

export PYTHONIOENCODING=utf-8

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "set-what-to-test.sh: $*" >&2; }
die() {
    local code="$1"
    shift
    log "$*"
    exit "$code"
}
usage() { die 2 "usage: ci_scripts/set-what-to-test.sh [--apply] --text-dir <dir>"; }

# argv: update <file> <localization-id> | create <file> <locale> <build-id>.
# The text is read from the file here, never passed through a shell string.
BODY_PY='
import json, sys
kind, path, ident = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    text = f.read().rstrip("\n")
if not text.strip():
    sys.exit("set-what-to-test.sh: empty text in " + path)
data = {"type": "betaBuildLocalizations"}
if kind == "update":
    data["id"] = ident
    data["attributes"] = {"whatsNew": text}
else:
    data["attributes"] = {"locale": ident, "whatsNew": text}
    data["relationships"] = {"build": {"data": {"type": "builds", "id": sys.argv[4]}}}
sys.stdout.write(json.dumps({"data": data}, separators=(",", ":")))
'

# argv: <mode> <response-file> [arg]. Ids end up in request paths, so only
# [A-Za-z0-9._-] is accepted.
QUERY_PY='
import json, re, sys
mode, path = sys.argv[1], sys.argv[2]
safe = re.compile(r"[A-Za-z0-9._-]+\Z")
def die(msg):
    sys.exit("set-what-to-test.sh: " + mode + ": " + msg)
try:
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
except ValueError as e:
    die("response is not JSON: " + str(e))
data = doc.get("data") if isinstance(doc, dict) else None
def ident(d):
    i = d.get("id") if isinstance(d, dict) else None
    if not isinstance(i, str) or not safe.match(i):
        die("response carries no usable data.id: " + repr(i))
    return i
def attrs(d):
    a = d.get("attributes") if isinstance(d, dict) else None
    return a if isinstance(a, dict) else {}
if mode == "written":
    ident(data)
    sys.exit(0)
if not isinstance(data, list):
    die("response has no data list")
if mode == "app":
    if len(data) != 1:
        die("expected exactly one app for the bundle id, got %d" % len(data))
    print(ident(data[0]))
elif mode == "build":
    hits = [d for d in data if attrs(d).get("version") == sys.argv[3]]
    if not hits:
        print("MISSING -")
    elif len(hits) > 1:
        die("%d builds match build number %s" % (len(hits), sys.argv[3]))
    else:
        print(attrs(hits[0]).get("processingState") or "UNKNOWN", ident(hits[0]))
elif mode == "localization":
    for d in data:
        if attrs(d).get("locale") == sys.argv[3]:
            print(ident(d))
            break
else:
    die("unknown mode")
'

apply=0
text_dir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply)    apply=1; shift ;;
        --text-dir) [ "$#" -ge 2 ] || usage; text_dir="$2"; shift 2 ;;
        *)          usage ;;
    esac
done
[ -n "$text_dir" ] || usage

command -v python3 >/dev/null 2>&1 || die 2 "python3 not found"

bundle_id="${CI_BUNDLE_ID:-}"
[ -n "$bundle_id" ] || die 2 "CI_BUNDLE_ID is not set"
case "$bundle_id" in
    *[!A-Za-z0-9.-]*) die 2 "CI_BUNDLE_ID has characters a bundle id cannot have: '$bundle_id'" ;;
esac

PROJECT_YML="${PROJECT_YML:-$ROOT/ios-app/project.yml}"
ASC_API="${ASC_API:-$ROOT/scripts/asc-api.sh}"
timeout_s="${WHAT_TO_TEST_TIMEOUT_S:-2700}"
poll_s="${WHAT_TO_TEST_POLL_S:-30}"
case "$timeout_s" in '' | *[!0-9]*) die 2 "WHAT_TO_TEST_TIMEOUT_S must be an integer, got '$timeout_s'" ;; esac
case "$poll_s" in '' | *[!0-9]* | 0) die 2 "WHAT_TO_TEST_POLL_S must be a positive integer, got '$poll_s'" ;; esac

# Same idiom as scripts/appstore-upload.sh.
yaml_value() { sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"]+)\"?[[:space:]]*$/\1/p" "$PROJECT_YML" | head -1; }
[ -f "$PROJECT_YML" ] || die 1 "missing $PROJECT_YML"
version="$(yaml_value MARKETING_VERSION)"
build="$(yaml_value CURRENT_PROJECT_VERSION)"
case "$version" in '' | *[!0-9.]*) die 1 "no usable MARKETING_VERSION in $PROJECT_YML: '$version'" ;; esac
case "$build" in '' | *[!0-9.]*) die 1 "no usable CURRENT_PROJECT_VERSION in $PROJECT_YML: '$build'" ;; esac

for loc in en-US de-DE; do
    [ -s "$text_dir/WhatToTest.$loc.txt" ] || die 1 "missing or empty $text_dir/WhatToTest.$loc.txt"
done

# body update <locale> <localization-id> | body create <locale> <build-id>
body() {
    local file="$text_dir/WhatToTest.$2.txt"
    if [ "$1" = update ]; then
        python3 -c "$BODY_PY" update "$file" "$3"
    else
        python3 -c "$BODY_PY" create "$file" "$2" "$3"
    fi
}

builds_path() {
    printf '/v1/builds?filter[app]=%s&filter[version]=%s&filter[preReleaseVersion.version]=%s&limit=5' \
        "$1" "$build" "$version"
}

if [ "$apply" -ne 1 ]; then
    echo "Dry run: nothing is sent. With --apply these requests go through $ASC_API:"
    echo "1. GET /v1/apps?filter[bundleId]=$bundle_id   (exactly one app expected)"
    echo "2. GET $(builds_path '<app-id>')   (every ${poll_s}s until processingState is VALID, at most ${timeout_s}s)"
    echo "3. GET /v1/builds/<build-id>/betaBuildLocalizations?limit=200"
    n=4
    for loc in en-US de-DE; do
        patch_body="$(body update "$loc" '<localization-id>')"
        post_body="$(body create "$loc" '<build-id>')"
        echo "$n. $loc, if listed in step 3: PATCH /v1/betaBuildLocalizations/<localization-id>"
        echo "   $patch_body"
        echo "   otherwise: POST /v1/betaBuildLocalizations"
        echo "   $post_body"
        n=$((n + 1))
    done
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
step=""

# asc <METHOD> <path> <response-file> [json-body]
asc() {
    local method="$1" path="$2" out="$3" rc
    shift 3
    log "$step: $method $path"
    if "$ASC_API" raw "$method" "$path" "$@" >"$out"; then
        return 0
    else
        rc=$?
    fi
    # asc-api.sh prints the response body to stdout, which is in $out: without this
    # Apple's error text never reaches the log. It carries no secret (the JWT only
    # travels in the request header).
    [ ! -s "$out" ] || { echo "response body:" >&2; head -c 2000 "$out" >&2; echo >&2; }
    die "$rc" "step '$step' failed: $method $path (exit $rc)"
}

q() { python3 -c "$QUERY_PY" "$@"; }

step="app lookup"
asc GET "/v1/apps?filter[bundleId]=$bundle_id" "$tmp/apps.json"
app_id="$(q app "$tmp/apps.json")"

step="build lookup"
deadline=$(($(date +%s) + timeout_s))
while :; do
    asc GET "$(builds_path "$app_id")" "$tmp/builds.json"
    hit="$(q build "$tmp/builds.json" "$build")"
    state="${hit%% *}"
    build_id="${hit#* }"
    # VALID is taken to mean "processing finished"; Apple lists the four states
    # without defining them.
    case "$state" in
        VALID) break ;;
        MISSING | PROCESSING) ;;
        FAILED | INVALID) die 1 "build $version ($build) is $state in App Store Connect; nothing to set" ;;
        *) die 1 "build $version ($build) has an unexpected processingState '$state'" ;;
    esac
    if [ "$(date +%s)" -ge "$deadline" ]; then
        die 1 "build $version ($build) was not VALID within ${timeout_s}s (last state: $state). Re-running this job is safe: it is idempotent."
    fi
    log "build $version ($build): $state, next check in ${poll_s}s"
    sleep "$poll_s"
done
log "build $version ($build) is VALID: $build_id"

step="localization list"
asc GET "/v1/builds/$build_id/betaBuildLocalizations?limit=200" "$tmp/localizations.json"

summary=""
for loc in en-US de-DE; do
    loc_id="$(q localization "$tmp/localizations.json" "$loc")"
    if [ -n "$loc_id" ]; then
        step="update $loc"
        payload="$(body update "$loc" "$loc_id")"
        asc PATCH "/v1/betaBuildLocalizations/$loc_id" "$tmp/$loc.json" "$payload"
        action=updated
    else
        step="create $loc"
        payload="$(body create "$loc" "$build_id")"
        asc POST /v1/betaBuildLocalizations "$tmp/$loc.json" "$payload"
        action=created
    fi
    q written "$tmp/$loc.json"
    summary="$summary$loc: $action (build $version ($build))
"
done
printf '%s' "$summary"
