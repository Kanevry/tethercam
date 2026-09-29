#!/usr/bin/env bash
# run.sh: contract tests for ci_scripts/what-to-test.sh, set-what-to-test.sh and
# write-asc-key.sh, and for scripts/asc-api.sh (T9). Self-contained: throw-away git
# repos, an App Store Connect stub and a throw-away EC key under one temp dir.
# Nothing reaches the network: refusing `curl` and `asc` stubs come first on PATH
# and only leave a marker file, whose existence after the run is a failure of its
# own (MARKER). T9 puts its own logging `curl` stub in front of them; it answers
# locally and never forwards to a real curl.
#
#   bash ci_scripts/tests/run.sh
#
# CI_SCRIPTS_DIR (default: the parent of this dir) selects the scripts under test
# and ASC_API_SH (default: <repo>/scripts/asc-api.sh) the API client, so a mutated
# copy can be checked. The scripts run under the same bash as this file. Exit 0
# only if every case passed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_SCRIPTS_DIR="${CI_SCRIPTS_DIR:-$(cd "$HERE/.." && pwd)}"
ASC_API_SH="${ASC_API_SH:-$(cd "$HERE/../.." && pwd)/scripts/asc-api.sh}"
BASH_BIN="${BASH:-bash}"
CASES="T1 T2 T3 T4 T5 T6 T7 T8 T9 MARKER"

for tool in git python3 base64 stat cmp openssl ps; do
    command -v "$tool" >/dev/null 2>&1 || { echo "run.sh: $tool not found" >&2; exit 2; }
done

# Nothing from the caller's environment may reach App Store Connect or steer a case.
unset ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH ASC_KEY_P8 ASC_API CI_TAG CI_BUNDLE_ID \
    PROJECT_YML WHAT_TO_TEST_TIMEOUT_S WHAT_TO_TEST_POLL_S \
    GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ci-scripts-tests.XXXXXX")" || exit 2
# Without this a failed mktemp leaves WORK empty and every path below resolves to /.
[ -d "$WORK" ] || exit 2
trap 'rm -rf "$WORK"' EXIT
RESULTS="$WORK/results"
MARKER="$WORK/network-marker"
: >"$RESULTS"

# The caller's git config (signing, hooks, templates) must not reach the fixtures.
export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
mkdir -p "$HOME" "$WORK/bin"

for name in curl asc; do
    printf '#!/bin/sh\necho "%s was called" >>"%s"\nexit 99\n' "$name" "$MARKER" >"$WORK/bin/$name"
    chmod +x "$WORK/bin/$name"
done
PATH="$WORK/bin:$PATH"
export PATH
# A case that forgets its own ASC_API meets the refusing stub, not scripts/asc-api.sh.
export ASC_API="$WORK/bin/asc"

# App Store Connect stand-in, used as ASC_API. Logs its argv as one JSON line and
# answers by path. STUB_BUILDS: valid | processing-then-valid | processing | failed.
STUB="$WORK/asc-stub"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@" >>"$STUB_LOG"
[ "${1:-}" = raw ] || { echo "stub: unexpected subcommand ${1:-}" >&2; exit 64; }
case "$2 $3" in
    "GET /v1/apps?"*)
        echo '{"data":[{"type":"apps","id":"app-1"}]}' ;;
    "GET /v1/builds?"*)
        n=$(( $(cat "$STUB_STATE/builds" 2>/dev/null || echo 0) + 1 ))
        echo "$n" >"$STUB_STATE/builds"
        case "${STUB_BUILDS:-valid}" in
            processing-then-valid) if [ "$n" -ge 3 ]; then st=VALID; else st=PROCESSING; fi ;;
            processing) st=PROCESSING ;;
            failed) st=FAILED ;;
            *) st=VALID ;;
        esac
        # Right after an upload the build is not listed yet: the first poll sees nothing.
        if [ "${STUB_BUILDS:-valid}" = processing-then-valid ] && [ "$n" -eq 1 ]; then
            echo '{"data":[]}'
        else
            printf '{"data":[{"type":"builds","id":"build-1","attributes":{"version":"42","processingState":"%s"}}]}\n' "$st"
        fi ;;
    "GET /v1/builds/build-1/betaBuildLocalizations"*)
        echo '{"data":[{"type":"betaBuildLocalizations","id":"loc-en","attributes":{"locale":"en-US","whatsNew":"old"}}]}' ;;
    "PATCH /v1/betaBuildLocalizations/"* | "POST /v1/betaBuildLocalizations")
        echo '{"data":{"type":"betaBuildLocalizations","id":"x"}}' ;;
    *)
        echo "stub: unexpected $2 $3" >&2; exit 65 ;;
esac
EOF
chmod +x "$STUB"

# Fixtures shared by T5-T7. The de-DE text differs from en-US on purpose, so a
# body built from the wrong locale's file is caught; it also carries a double
# quote, a backslash, a newline and non-ASCII text that JSON has to escape.
FIX="$WORK/fixtures"
mkdir -p "$FIX/text"
printf '    MARKETING_VERSION: "1.2.3"\n    CURRENT_PROJECT_VERSION: "42"\n' >"$FIX/project.yml"
printf -- '- en: plain line\n' >"$FIX/text/WhatToTest.en-US.txt"
printf -- '- de: Modus "Studio" mit \\ Backslash\n- zweite Zeile: Größe\n' >"$FIX/text/WhatToTest.de-DE.txt"

record() {  # record <case> <PASS|FAIL> [reason]
    printf '%s %s%s\n' "$2" "$1" "${3:+: $3}" >>"$RESULTS"
    printf '%s %s%s\n' "$2" "$1" "${3:+: $3}"
}

WHY=""
bad() { printf '%s\n' "$*" >>"$WHY"; }
snip() { tr '\n' ' ' <"$1" | cut -c1-400; }

# run_to <seconds> <cmd...>: timeout(1) where it exists; stock macOS has none.
run_to() {
    local secs="$1" pid watcher rc
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
        return
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
        return
    fi
    "$@" &
    pid=$!
    ( sleep "$secs"; kill -TERM "$pid" ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    rc=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    return "$rc"
}

# run_script <dir> <cmd...>: stdout/stderr to <dir>/stdout and <dir>/stderr; sets RC, ELAPSED.
RC=0
ELAPSED=0
run_script() {
    local d="$1" start
    shift
    start=$SECONDS
    run_to 60 "$@" >"$d/stdout" 2>"$d/stderr"
    RC=$?
    ELAPSED=$((SECONDS - start))
}

COMMIT_N=0
make_repo() { git -c init.defaultBranch=main init -q "$1"; }
commit() {  # commit <repo> <subject>: empty commit with a fixed, increasing date
    COMMIT_N=$((COMMIT_N + 1))
    GIT_AUTHOR_DATE="$((1700000000 + COMMIT_N)) +0000" \
        GIT_COMMITTER_DATE="$((1700000000 + COMMIT_N)) +0000" \
        git -C "$1" commit -q --allow-empty -m "$2"
}

wtt() { run_script "$1" env CI_TAG="$2" "$BASH_BIN" "$CI_SCRIPTS_DIR/what-to-test.sh" "${@:3}"; }
swt() { run_script "$1" env CI_BUNDLE_ID=at.example.app PROJECT_YML="$FIX/project.yml" \
    ASC_API="$STUB" STUB_LOG="$1/stub.log" STUB_STATE="$1" "${@:2}"; }

no_output_files() {  # no_output_files <out-dir>
    [ ! -e "$1/WhatToTest.en-US.txt" ] && [ ! -e "$1/WhatToTest.de-DE.txt" ]
}

# T1: the annotation body is the text, cleaned, without the tag's subject line.
T1() {
    local d="$WORK/t1" r="$WORK/t1/repo"
    mkdir -p "$d"
    if ! { make_repo "$r" && commit "$r" "feat: camera mode"; }; then
        bad "fixture"
        return 1
    fi
    # \140 is a backtick.
    printf 'TetherCam v1.0.0\n\n- **Camera: new mode.** Uses \140HEVC\140 now.   \n  Second line of the item.\n\n\n\n- Fix: plain item\n\n' >"$d/msg"
    git -C "$r" tag -a --cleanup=verbatim -F "$d/msg" v1.0.0 || { bad "fixture tag"; return 1; }
    printf -- '- Camera: new mode. Uses HEVC now.\n  Second line of the item.\n\n- Fix: plain item\n' >"$d/expected"
    cd "$r" || return 1
    run_script "$d" env CI_TAG=v1.0.0 "$BASH_BIN" "$CI_SCRIPTS_DIR/what-to-test.sh" --out-dir "$d/text"
    [ "$RC" -eq 0 ] || { bad "exit $RC: $(snip "$d/stderr")"; return 1; }
    cmp -s "$d/text/WhatToTest.en-US.txt" "$d/expected" \
        || { bad "en-US text is not the cleaned annotation body: $(snip "$d/text/WhatToTest.en-US.txt")"; return 1; }
    cmp -s "$d/text/WhatToTest.en-US.txt" "$d/text/WhatToTest.de-DE.txt" \
        || { bad "de-DE text differs from en-US"; return 1; }
}

# T2: empty annotation and lightweight tag both fall back to feat/fix/perf subjects
# since the previous v* tag, filtered and stripped.
T2() {
    local d="$WORK/t2" r="$WORK/t2/repo" sub
    mkdir -p "$d"
    {
        make_repo "$r" &&
            commit "$r" "feat: ancient feature" &&
            git -C "$r" tag v0.9.0 &&
            commit "$r" "feat(app): new camera mode (#12, #13)" &&
            commit "$r" "docs: readme update" &&
            commit "$r" "fix: crash on unplug (#14)" &&
            git -C "$r" checkout -q -b side &&
            commit "$r" "feat: side branch work" &&
            git -C "$r" checkout -q main &&
            commit "$r" "chore: bump version" &&
            GIT_COMMITTER_DATE="1700000900 +0000" git -C "$r" merge -q --no-ff --no-edit \
                -m "feat: merged side branch" side &&
            commit "$r" "feat(web): landing page" &&
            commit "$r" "fix(ci, app): runner image" &&
            commit "$r" "perf(scripts): faster lookup" &&
            commit "$r" "feat(release): tag helper" &&
            commit "$r" "feat!: breaking protocol change" &&
            commit "$r" "fix(App,UI): scaled preview" &&
            commit "$r" "perf: quicker decode (#15)" &&
            git -C "$r" tag -a -m "TetherCam v1.0.0" v1.0.0 &&
            git -C "$r" tag v1.0.0-lw
    } >/dev/null 2>&1 || { bad "fixture"; return 1; }
    printf -- '- %s\n' "breaking protocol change" "crash on unplug" "new camera mode" \
        "quicker decode" "scaled preview" "side branch work" | LC_ALL=C sort >"$d/expected"
    cd "$r" || return 1
    for sub in v1.0.0 v1.0.0-lw; do
        mkdir -p "$d/$sub"
        wtt "$d/$sub" "$sub" --out-dir "$d/$sub/text"
        [ "$RC" -eq 0 ] || { bad "$sub: exit $RC: $(snip "$d/$sub/stderr")"; return 1; }
        LC_ALL=C sort "$d/$sub/text/WhatToTest.en-US.txt" >"$d/$sub/sorted"
        cmp -s "$d/$sub/sorted" "$d/expected" \
            || { bad "$sub: fallback lines differ: $(snip "$d/$sub/sorted")"; return 1; }
    done
}

# T3: no annotation body and no usable commit: an error, and no file at all.
T3() {
    local d="$WORK/t3" r="$WORK/t3/repo"
    mkdir -p "$d"
    {
        make_repo "$r" && commit "$r" "docs: only docs" && commit "$r" "chore: tidy" &&
            git -C "$r" tag -a -m "TetherCam v2.0.0" v2.0.0
    } >/dev/null 2>&1 || { bad "fixture"; return 1; }
    cd "$r" || return 1
    wtt "$d" v2.0.0 --out-dir "$d/text"
    [ "$RC" -eq 1 ] || { bad "exit $RC, want 1: $(snip "$d/stderr")"; return 1; }
    no_output_files "$d/text" || { bad "files written despite the failure"; return 1; }
}

# T4: the commit fallback refuses a shallow clone instead of reading a cut range.
T4() {
    local d="$WORK/t4" r="$WORK/t4/origin" c="$WORK/t4/clone"
    mkdir -p "$d"
    {
        make_repo "$r" && commit "$r" "feat: old feature" && commit "$r" "feat: head feature" &&
            git -C "$r" tag -a -m "TetherCam v1.0.0" v1.0.0 &&
            git clone -q --depth 1 "file://$r" "$c"
    } >/dev/null 2>&1 || { bad "fixture"; return 1; }
    if [ "$(git -C "$c" rev-parse --is-shallow-repository)" != true ] \
        || ! git -C "$c" rev-parse -q --verify refs/tags/v1.0.0 >/dev/null; then
        bad "fixture: clone is not shallow or lacks the tag"
        return 1
    fi
    cd "$c" || return 1
    wtt "$d" v1.0.0 --out-dir "$d/text"
    [ "$RC" -eq 3 ] || { bad "exit $RC, want 3: $(snip "$d/stderr")"; return 1; }
    grep -q 'fetch-depth' "$d/stderr" || { bad "message does not name fetch-depth"; return 1; }
    no_output_files "$d/text" || { bad "files written despite the failure"; return 1; }
}

# T5: without --apply nothing is invoked, the planned bodies are shown.
T5() {
    local d="$WORK/t5"
    mkdir -p "$d"
    swt "$d" "$BASH_BIN" "$CI_SCRIPTS_DIR/set-what-to-test.sh" --text-dir "$FIX/text"
    [ "$RC" -eq 0 ] || { bad "exit $RC: $(snip "$d/stderr")"; return 1; }
    [ ! -s "$d/stub.log" ] || { bad "dry run invoked ASC_API: $(snip "$d/stub.log")"; return 1; }
    [ ! -e "$MARKER" ] || { bad "dry run reached curl/asc"; return 1; }
    if ! { grep -q 'PATCH /v1/betaBuildLocalizations/<localization-id>' "$d/stdout" \
        && grep -q 'POST /v1/betaBuildLocalizations' "$d/stdout" \
        && grep -q '"whatsNew":"- de: Modus' "$d/stdout" \
        && grep -q '"id":"<build-id>"' "$d/stdout"; }; then
        bad "dry run does not show the PATCH/POST bodies: $(snip "$d/stdout")"
        return 1
    fi
}

# T6: --apply lists first, PATCHes the existing locale, POSTs the missing one with
# a correctly escaped body, and polls until the build is VALID.
T6() {
    local d="$WORK/t6"
    mkdir -p "$d"
    swt "$d" STUB_BUILDS=processing-then-valid WHAT_TO_TEST_POLL_S=1 WHAT_TO_TEST_TIMEOUT_S=30 \
        "$BASH_BIN" "$CI_SCRIPTS_DIR/set-what-to-test.sh" --apply --text-dir "$FIX/text"
    [ "$RC" -eq 0 ] || { bad "exit $RC: $(snip "$d/stderr")"; return 1; }
    if ! { grep -q '^en-US: updated' "$d/stdout" && grep -q '^de-DE: created' "$d/stdout"; }; then
        bad "summary lines missing: $(snip "$d/stdout")"
        return 1
    fi
    cat >"$d/check.py" <<'EOF'
import json, sys
log, en_path, de_path = sys.argv[1:4]
calls = [json.loads(line) for line in open(log, encoding="utf-8")]
def text(p):
    return open(p, encoding="utf-8").read().rstrip("\n")
def fail(msg):
    print(msg)
    sys.exit(1)
if any(c[0] != "raw" for c in calls):
    fail("a call did not use the raw subcommand")
def pick(method, prefix):
    return [i for i, c in enumerate(calls) if c[1] == method and c[2].startswith(prefix)]
apps, builds = pick("GET", "/v1/apps?"), pick("GET", "/v1/builds?")
lists = pick("GET", "/v1/builds/build-1/betaBuildLocalizations")
patches, posts = pick("PATCH", "/"), pick("POST", "/")
counts = (len(calls), len(apps), len(builds), len(lists), len(patches), len(posts))
if counts != (7, 1, 3, 1, 1, 1):
    fail("calls (total, apps, builds, list, patch, post) = %r, want (7, 1, 3, 1, 1, 1)" % (counts,))
if "filter[bundleId]=at.example.app" not in calls[apps[0]][2]:
    fail("app lookup path: " + calls[apps[0]][2])
for part in ("filter[app]=app-1", "filter[version]=42", "filter[preReleaseVersion.version]=1.2.3"):
    if part not in calls[builds[0]][2]:
        fail("build lookup path lacks " + part + ": " + calls[builds[0]][2])
if not lists[0] < min(patches[0], posts[0]):
    fail("a localization was written before the list was read")
patch = calls[patches[0]]
if patch[2] != "/v1/betaBuildLocalizations/loc-en":
    fail("PATCH path: " + patch[2])
want = {"data": {"type": "betaBuildLocalizations", "id": "loc-en", "attributes": {"whatsNew": text(en_path)}}}
if json.loads(patch[3]) != want:
    fail("PATCH body: " + patch[3])
post = calls[posts[0]]
if post[2] != "/v1/betaBuildLocalizations":
    fail("POST path: " + post[2])
want = {"data": {"type": "betaBuildLocalizations",
                 "attributes": {"locale": "de-DE", "whatsNew": text(de_path)},
                 "relationships": {"build": {"data": {"type": "builds", "id": "build-1"}}}}}
if json.loads(post[3]) != want:
    fail("POST body: " + post[3])
EOF
    python3 "$d/check.py" "$d/stub.log" "$FIX/text/WhatToTest.en-US.txt" \
        "$FIX/text/WhatToTest.de-DE.txt" >"$d/check.out" 2>&1 \
        || { bad "$(snip "$d/check.out")"; return 1; }
}

# T7: FAILED stops at once; PROCESSING forever stops at the deadline with a hint.
T7() {
    local d="$WORK/t7"
    mkdir -p "$d/failed" "$d/stuck"
    swt "$d/failed" STUB_BUILDS=failed WHAT_TO_TEST_POLL_S=1 WHAT_TO_TEST_TIMEOUT_S=30 \
        "$BASH_BIN" "$CI_SCRIPTS_DIR/set-what-to-test.sh" --apply --text-dir "$FIX/text"
    [ "$RC" -ne 0 ] || { bad "failed: exit 0"; return 1; }
    [ "$ELAPSED" -le 5 ] || { bad "failed: took ${ELAPSED}s, kept polling a FAILED build"; return 1; }
    grep -q FAILED "$d/failed/stderr" || { bad "failed: message does not name FAILED"; return 1; }
    if grep -q '"PATCH"\|"POST"' "$d/failed/stub.log"; then
        bad "failed: wrote a localization anyway"
        return 1
    fi
    swt "$d/stuck" STUB_BUILDS=processing WHAT_TO_TEST_POLL_S=1 WHAT_TO_TEST_TIMEOUT_S=3 \
        "$BASH_BIN" "$CI_SCRIPTS_DIR/set-what-to-test.sh" --apply --text-dir "$FIX/text"
    [ "$RC" -ne 0 ] || { bad "stuck: exit 0"; return 1; }
    [ "$ELAPSED" -le 10 ] || { bad "stuck: took ${ELAPSED}s (exit $RC), deadline not honoured"; return 1; }
    grep -qi 're-run' "$d/stuck/stderr" || { bad "stuck: message does not mention re-running: $(snip "$d/stuck/stderr")"; return 1; }
}

# GNU first: on GNU stat "-f" means file-system mode and prints to stdout before failing.
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# T8: the key lands decoded, mode 600 even over an existing file, and silent.
T8() {
    local d="$WORK/t8" key="fake-p8 not a real key" b64 mode
    mkdir -p "$d/empty"
    b64="$(printf %s "$key" | base64)"
    printf 'stale\n' >"$d/AuthKey.p8"
    chmod 644 "$d/AuthKey.p8"
    run_script "$d" env ASC_KEY_P8="$b64" "$BASH_BIN" "$CI_SCRIPTS_DIR/write-asc-key.sh" "$d/AuthKey.p8"
    [ "$RC" -eq 0 ] || { bad "exit $RC: $(snip "$d/stderr")"; return 1; }
    [ ! -s "$d/stdout" ] || { bad "printed to stdout"; return 1; }
    if grep -qF "$b64" "$d/stderr" || grep -qF "$key" "$d/stderr"; then
        bad "the key value appears on stderr"
        return 1
    fi
    [ "$(cat "$d/AuthKey.p8")" = "$key" ] || { bad "decoded content differs"; return 1; }
    mode="$(file_mode "$d/AuthKey.p8")"
    [ "$mode" = 600 ] || { bad "mode $mode, want 600"; return 1; }
    run_script "$d/empty" env ASC_KEY_P8= "$BASH_BIN" "$CI_SCRIPTS_DIR/write-asc-key.sh" "$d/empty/AuthKey.p8"
    [ "$RC" -ne 0 ] || { bad "empty ASC_KEY_P8: exit 0"; return 1; }
    [ ! -e "$d/empty/AuthKey.p8" ] || { bad "empty ASC_KEY_P8: file written"; return 1; }
}

# T9: the App Store Connect JWT reaches curl on stdin, never in its argv (#36).
# Both request() branches run (GET without a body, POST with one); every broken
# check is reported. Messages carry only counts, call numbers and file names:
# the logs hold the test JWT.
T9() {
    local d="$WORK/t9" root="$WORK/t9/root" n f sub calls fail=0 jwt='eyJ[A-Za-z0-9_-]{10,}\.'
    local -a api
    mkdir -p "$d/bin" "$d/log" "$d/tmp" "$d/get" "$d/post" "$root/scripts"
    # A copy in a temp root: run in place, the script would source the checkout's .env.local.
    cp "$ASC_API_SH" "$root/scripts/asc-api.sh" || { bad "fixture: copy $ASC_API_SH"; return 1; }
    [ ! -e "$root/.env.local" ] || { bad "fixture: $root/.env.local exists"; return 1; }
    openssl ecparam -genkey -name prime256v1 -noout -out "$d/key.pem" 2>/dev/null \
        || { bad "fixture: openssl ecparam"; return 1; }
    # Logs argv, its own ps line and stdin per call, then answers 200 with {}. POSIX sh.
    cat >"$d/bin/curl" <<'EOF'
#!/bin/sh
n=$(( $(cat "$T9_LOG/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$T9_LOG/count"
printf '%s\n' "$@" >"$T9_LOG/argv.$n"
ps -ww -o command= -p $$ >"$T9_LOG/ps.$n" 2>&1
cat >"$T9_LOG/stdin.$n"
out=''
prev=''
for a in "$@"; do
    [ "$prev" = -o ] && out=$a
    prev=$a
done
[ -z "$out" ] || printf '{}' >"$out"
printf 200
EOF
    chmod +x "$d/bin/curl"
    api=(env -i PATH="$d/bin:$PATH" HOME="$HOME" TMPDIR="$d/tmp" T9_LOG="$d/log"
        ASC_KEY_ID=TESTKEY123 ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
        ASC_KEY_PATH="$d/key.pem" "$BASH_BIN" "$root/scripts/asc-api.sh" raw)
    # </dev/null: where curl inherits stdin, the stub's cat would otherwise block until run_to.
    run_script "$d/get" "${api[@]}" GET /v1/x </dev/null
    [ "$RC" -eq 0 ] || { bad "call 1 (GET): exit $RC"; fail=1; }
    run_script "$d/post" "${api[@]}" POST /v1/x '{"a":1}' </dev/null
    [ "$RC" -eq 0 ] || { bad "call 2 (POST): exit $RC"; fail=1; }

    calls=0
    [ -f "$d/log/count" ] && calls="$(tr -cd 0-9 <"$d/log/count")"
    [ "$calls" = 2 ] || { bad "stub curl called ${calls:-0} times, want 2"; fail=1; }
    printf '{}' >"$d/want-stdout"
    for sub in get post; do
        cmp -s "$d/$sub/stdout" "$d/want-stdout" || { bad "$sub: stdout is not the stub's {}"; fail=1; }
        for f in stdout stderr; do
            if grep -Eq "$jwt" "$d/$sub/$f"; then bad "$sub: a JWT appears on its $f"; fail=1; fi
        done
    done
    for n in 1 2; do
        for f in argv ps stdin; do
            [ -f "$d/log/$f.$n" ] || { bad "call $n: $f.$n missing"; fail=1; }
        done
        for f in argv ps; do
            [ -f "$d/log/$f.$n" ] || continue
            grep -qF /v1/x "$d/log/$f.$n" || { bad "call $n: $f.$n lacks the request path"; fail=1; }
            if grep -qF Bearer "$d/log/$f.$n" || grep -Eq "$jwt" "$d/log/$f.$n"; then
                bad "call $n: Authorization header or JWT in curl's $f"
                fail=1
            fi
        done
        [ -f "$d/log/stdin.$n" ] || continue
        if ! grep -Eq 'Authorization: Bearer eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$d/log/stdin.$n"; then
            bad "call $n: no Authorization: Bearer <JWT> on curl's stdin"
            fail=1
        fi
    done
    # Branch controls: the body is curl's last argument, so ps.2 also proves no truncation.
    if [ -f "$d/log/argv.2" ] && ! grep -qxF '{"a":1}' "$d/log/argv.2"; then
        bad "call 2: argv.2 lacks the JSON body"
        fail=1
    fi
    if [ -f "$d/log/ps.2" ] && ! grep -qF '{"a":1}' "$d/log/ps.2"; then
        bad "call 2: ps.2 lacks the JSON body (truncated?)"
        fail=1
    fi
    if [ -f "$d/log/argv.1" ] && grep -qx -- --data "$d/log/argv.1"; then
        bad "call 1: argv.1 carries --data, GET did not take the no-body branch"
        fail=1
    fi
    [ "$fail" -eq 0 ]
}

for c in $CASES; do
    [ "$c" = MARKER ] && continue
    WHY="$WORK/why.$c"
    : >"$WHY"
    if ( "$c" ); then
        record "$c" PASS
    else
        record "$c" FAIL "$(tr '\n' ' ' <"$WHY")"
    fi
done

if [ -e "$MARKER" ]; then
    record MARKER FAIL "a stub curl/asc was called: $(snip "$MARKER")"
else
    record MARKER PASS
fi

# The verdict comes from the results file, never from captured output.
passed="$(grep -c '^PASS ' "$RESULTS" || true)"
failed="$(grep -c '^FAIL ' "$RESULTS" || true)"
want=0
for c in $CASES; do want=$((want + 1)); done
echo "ci_scripts tests: $passed passed, $failed failed, $want expected"
[ "$failed" -eq 0 ] && [ "$passed" -eq "$want" ]
