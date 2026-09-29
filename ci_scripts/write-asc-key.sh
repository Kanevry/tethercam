#!/usr/bin/env bash
# write-asc-key.sh: decode the App Store Connect API key into a file only the
# current user can read. Prints nothing on stdout.
#
#   ci_scripts/write-asc-key.sh <target-path>
#
# Env read: ASC_KEY_P8 (the .p8 file, base64-encoded; a CI secret). Never echo
# the value or anything derived from it: CI logs are public on a public repo.
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: ci_scripts/write-asc-key.sh <target-path>" >&2
    exit 2
fi
target="$1"

if [ -z "${ASC_KEY_P8:-}" ]; then
    echo "::error::ASC_KEY_P8 is not set. Nothing can talk to App Store Connect without it." >&2
    exit 1
fi

umask 077
if ! printf %s "$ASC_KEY_P8" | base64 --decode >"$target"; then
    rm -f "$target"
    echo "::error::ASC_KEY_P8 is not valid base64." >&2
    exit 1
fi
# umask only covers a new file; an existing one keeps its mode without this.
chmod 600 "$target"
if [ ! -s "$target" ]; then
    rm -f "$target"
    echo "::error::decoded API key is empty" >&2
    exit 1
fi
