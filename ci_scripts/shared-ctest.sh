#!/usr/bin/env bash
# shared-ctest.sh: configure, build and test the shared/ C core. The one body
# behind GitLab's shared-ctest job and ci-plugin.yml's shared-tests job.
#
#   ci_scripts/shared-ctest.sh <build-dir> [cmake configure args...]
#
# <build-dir> is relative to the repo root; the extra arguments go to the
# configure step only.
set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
    echo "usage: ci_scripts/shared-ctest.sh <build-dir> [cmake configure args...]" >&2
    exit 2
fi
build_dir="$1"
shift

cd "$(dirname "${BASH_SOURCE[0]}")/.."

cmake -S shared -B "$build_dir" "$@"
cmake --build "$build_dir"
ctest --test-dir "$build_dir" --output-on-failure
