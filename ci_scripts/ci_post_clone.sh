#!/usr/bin/env bash
# ci_post_clone.sh: generate the Xcode project right after the clone. The name
# follows Apple's ci_scripts convention for the post-clone hook; Xcode Cloud itself
# is not used, the GitHub workflows call this script as a step.
#
# Contract variable read: CI_PRODUCT_PLATFORM (iOS -> ios-app, macOS -> mac-app).
set -euo pipefail

case "${CI_PRODUCT_PLATFORM:-}" in
    iOS)   project_dir=ios-app ;;
    macOS) project_dir=mac-app ;;
    *)
        echo "ci_post_clone.sh: CI_PRODUCT_PLATFORM must be iOS or macOS, got '${CI_PRODUCT_PLATFORM:-}'" >&2
        exit 2
        ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/../$project_dir"

brew install xcodegen
xcodegen generate
