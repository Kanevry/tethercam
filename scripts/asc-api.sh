#!/usr/bin/env bash
# asc-api.sh: minimal App Store Connect API client. No gem, no node, no fastlane.
#
#   scripts/asc-api.sh apps                 list the team's app records
#   scripts/asc-api.sh bundle-ids           list registered bundle ids
#   scripts/asc-api.sh builds <appId>       list uploaded builds of one app
#   scripts/asc-api.sh raw GET  /v1/users
#   scripts/asc-api.sh raw POST /v1/bundleIds '{"data":{...}}'
#
# Authentication is an ES256 JWT signed with the App Store Connect .p8 key. The
# key path stays outside the repository; key id and issuer id are identifiers, not
# secrets, and can be overridden by the environment or a git-ignored .env.local:
#
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
#
# The token is NEVER printed and never written to disk; it lives in a shell
# variable for the duration of one curl call. Output is raw JSON — pipe to jq.
set -euo pipefail

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="https://api.appstoreconnect.apple.com"

if [ -f "$ROOT/.env.local" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$ROOT/.env.local"
    set +a
fi

[ -n "${ASC_KEY_ID:-}" ] || die "ASC_KEY_ID is not set (env or .env.local). See docs/SECRETS.md."
[ -n "${ASC_ISSUER_ID:-}" ] || die "ASC_ISSUER_ID is not set (env or .env.local). See docs/SECRETS.md."
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

[ -f "$ASC_KEY_PATH" ] || die "App Store Connect key not found at $ASC_KEY_PATH (set ASC_KEY_PATH)"
command -v openssl >/dev/null || die "openssl not found"
command -v python3 >/dev/null || die "python3 not found"

# base64url without padding, reading stdin.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Mints a short-lived ES256 JWT. Apple accepts a lifetime of at most 20 minutes;
# 10 is plenty for one command and shrinks the window if the value ever leaks.
mint_token() {
    local now exp header payload signing_input sig
    now="$(date +%s)"
    exp="$((now + 600))"
    header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | b64url)"
    payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' \
        "$ASC_ISSUER_ID" "$now" "$exp" | b64url)"
    signing_input="$header.$payload"

    # openssl emits an ASN.1/DER ECDSA signature; JWS needs the raw r||s pair,
    # each zero-padded to 32 bytes for P-256. Converted here in python3 so the
    # script stays dependency-free.
    sig="$(printf '%s' "$signing_input" \
        | openssl dgst -sha256 -sign "$ASC_KEY_PATH" \
        | python3 -c '
import sys, base64
der = sys.stdin.buffer.read()
# SEQUENCE { INTEGER r, INTEGER s }
i = 2 if der[1] < 0x80 else 3
def rd(buf, i):
    assert buf[i] == 0x02, "not an INTEGER"
    n = buf[i + 1]
    return int.from_bytes(buf[i + 2:i + 2 + n], "big"), i + 2 + n
r, i = rd(der, i)
s, _ = rd(der, i)
raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
sys.stdout.write(base64.urlsafe_b64encode(raw).decode().rstrip("="))
')"
    printf '%s.%s' "$signing_input" "$sig"
}

# request METHOD PATH [JSON-BODY]
request() {
    local method="$1" path="$2" body="${3:-}" token status out
    case "$path" in
        /*) ;;
        *)  path="/$path" ;;
    esac
    token="$(mint_token)"
    out="$(mktemp)"
    # -g: do not glob [] in query strings such as filter[bundleId].
    if [ -n "$body" ]; then
        status="$(curl -sg -o "$out" -w '%{http_code}' -X "$method" "$API$path" \
            -H "Authorization: Bearer $token" \
            -H 'Content-Type: application/json' \
            --data "$body")"
    else
        status="$(curl -sg -o "$out" -w '%{http_code}' -X "$method" "$API$path" \
            -H "Authorization: Bearer $token")"
    fi
    unset token
    cat "$out"
    rm -f "$out"
    case "$status" in
        2*) ;;
        401|403) echo >&2; die "HTTP $status: the key lacks the required role, or the JWT was rejected." ;;
        *)  echo >&2; die "HTTP $status for $method $path" ;;
    esac
}

CMD="${1:-}"
[ -n "$CMD" ] || { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }
shift

case "$CMD" in
    apps)
        request GET '/v1/apps?limit=200&fields[apps]=name,bundleId,sku,primaryLocale'
        ;;
    bundle-ids)
        request GET '/v1/bundleIds?limit=200&fields[bundleIds]=identifier,name,platform,seedId'
        ;;
    builds)
        APP_ID="${1:-}"
        [ -n "$APP_ID" ] || die "usage: asc-api.sh builds <appId>   (get the id from: asc-api.sh apps)"
        request GET "/v1/builds?filter[app]=$APP_ID&limit=50&sort=-uploadedDate&fields[builds]=version,uploadedDate,processingState,expired"
        ;;
    raw)
        METHOD="${1:-}"; RAW_PATH="${2:-}"; RAW_BODY="${3:-}"
        [ -n "$METHOD" ] && [ -n "$RAW_PATH" ] || die "usage: asc-api.sh raw <GET|POST|PATCH|DELETE> <path> [json]"
        request "$METHOD" "$RAW_PATH" "$RAW_BODY"
        ;;
    -h|--help|help)
        sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        ;;
    *)
        die "unknown subcommand: $CMD (apps | bundle-ids | builds <appId> | raw)"
        ;;
esac
