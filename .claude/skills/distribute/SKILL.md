---
name: distribute
description: Ship TetherCam's two artefacts — the iOS app to TestFlight and the OBS plugin as a signed, notarized .pkg on a GitHub release. Use when asked to release, distribute, upload to TestFlight, cut a version, publish the plugin, or check why a release asset 404s.
allowed-tools: Bash
---

# Distribute TetherCam

Two artefacts, one tag. `vX.Y.Z` pushed to `github` triggers both workflows on
`Kanevry/tethercam`. The iOS app can also be shipped locally with
`scripts/appstore-upload.sh`, which is the same flow the workflow runs.

Never edit `packaging/ExportOptions.plist` to do a local export — pass `--dry-run`,
which works on a temp copy. Never print a `.p8` or a JWT.

## State as of 2026-09-05 — read this before promising a release

| Thing | State |
|---|---|
| GitHub secrets `ASC_KEY_P8` / `ASC_KEY_ID` / `ASC_ISSUER_ID` | set |
| GitHub secrets `NOTARY_KEY_P8` / `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID` | set (same key) |
| Bundle id `at.gotzendorfer.tethercam` | registered (`2G7A77TNZ6`, UNIVERSAL) |
| App Store Connect **app record** | **MISSING — blocks every TestFlight upload** |
| Developer ID **Installer** certificate + `MACOS_INSTALLER_CERT_P12` | **MISSING — the .pkg ships unsigned and unnotarized** |
| Local key | `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`; key id and issuer id live in the git-ignored `.env.local` (`ASC_KEY_ID`, `ASC_ISSUER_ID`) |

Both missing items are **owner steps** — no API key can create them. See
`docs/RELEASING.md` §1b and §1d.

## A. iOS to TestFlight

### Locally (preferred for a first upload — the error messages are readable)

```bash
scripts/appstore-upload.sh --dry-run     # archive + export .ipa, nothing uploaded
scripts/appstore-upload.sh               # archive + upload to App Store Connect
```

Flags: `--version X.Y.Z`, `--build-number N` override `ios-app/project.yml`.
Full logs land in `build/appstore-*.log` (git-ignored). Expect `Authority=Apple
Distribution: Bernhard Goetzendorfer (G3QZ66475M)` in the codesign summary; a
`Apple Development` authority means the export picked the wrong profile.

If it dies with *"No suitable application records were found"*, the app record is
missing — the script prints the exact New-App form to fill in. That is a website-only
step for the Account Holder.

### Via CI

`.github/workflows/testflight-ios.yml` runs on any `v*` tag push and on
`workflow_dispatch` (optional `bundle_id` input). It skips itself cleanly when
`ASC_KEY_P8` is unset, so a fork never sees a red X.

### After the upload

Processing is 5-30 min. Then:

```bash
scripts/asc-api.sh apps | jq '.data[] | select(.attributes.bundleId=="at.gotzendorfer.tethercam")'
scripts/asc-api.sh builds <appId> | jq '.data[0].attributes'
```

Internal testers get the build immediately. A **public** link needs an external
group plus a one-time Beta App Review (a day or two) — see `docs/RELEASING.md` §2.

## B. OBS plugin .pkg

Built only by `.github/workflows/release-plugin.yml` on the `v*` tag. Do not build
release artefacts by hand; the workflow does the keychain import, `productbuild`,
notarization, stapling and checksums in the order Apple requires.

Until `MACOS_INSTALLER_CERT_P12` exists the workflow still succeeds: it warns, skips
notarization, and the `.pkg` it publishes is blocked by Gatekeeper on every machine
but the build host. Say so plainly when reporting — do not call that release
"distributable".

## C. Release order (from docs/RELEASING.md §3) — the publish step is the one people forget

```bash
git status                                   # clean tree, CHANGELOG Unreleased is real
scripts/release.sh 0.1.1                     # bumps buildspec.json, project.yml, CHANGELOG
git diff                                     # read it
git add obs-plugin/buildspec.json ios-app/project.yml CHANGELOG.md
git commit -m "chore(release): 0.1.1"
scripts/release.sh 0.1.1 --tag               # refuses if the bump is not committed
git push origin HEAD && git push origin v0.1.1
git push github HEAD && git push github v0.1.1    # THIS starts the workflows
gh run watch --repo Kanevry/tethercam
```

The workflow creates a **draft** release. Publish it in the GitHub UI (or
`gh release edit v0.1.1 --draft=false --repo Kanevry/tethercam`). Until it is
published, `releases/latest/download/...` — which the website and
`scripts/install.sh` use — returns 404.

## D. Verify before announcing

```bash
# The one check that catches an unpublished draft. Expect 302, not 404.
curl -sI https://github.com/Kanevry/tethercam/releases/latest/download/TetherCam-obs-plugin.pkg | head -1

gh release download v0.1.1 --repo Kanevry/tethercam --dir /tmp/verify && cd /tmp/verify
shasum -a 256 -c TetherCam-obs-plugin.pkg.sha256
spctl -a -t install -vv TetherCam-obs-plugin.pkg    # want: accepted, Notarized Developer ID
xcrun stapler validate TetherCam-obs-plugin.pkg
```

`spctl` is the verdict that matters — it is what a machine that has never seen the
certificate will say. A signed-but-unnotarized `.pkg` fails here, correctly.

## E. Report

- Version and build number, and which of the two artefacts actually shipped.
- The `.ipa` path and the codesign Authority line (dry run), or the App Store Connect
  processing state (real upload).
- The `curl -sI` status code for the plugin asset: 302 or 404.
- Any owner step still blocking: app record, installer certificate.
- Never paste key material, a JWT, or the contents of `build/appstore-*.log`.
