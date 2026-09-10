# Homebrew casks (live)

Two casks, both published to the personal tap `Kanevry/homebrew-tethercam`
(https://github.com/Kanevry/homebrew-tethercam). The files here are the repo's copy of
what is in the tap; the tap is the thing Homebrew reads.

| File | Cask | Installs | Asset |
|---|---|---|---|
| `tethercam.rb` | `tethercam` | The Mac app: menu bar host plus camera extension, so the iPhone shows up as the system camera "TetherCam" in Zoom, Teams, Meet, FaceTime, QuickTime and every other Mac app. Default path. | `TetherCam-mac.dmg` |
| `tethercam-obs.rb` | `tethercam-obs` | The OBS Studio source plugin, with audio from the phone. Pro path. | `TetherCam-obs-plugin.zip` |

```sh
brew tap kanevry/tethercam
brew install --cask tethercam        # Mac app, any Mac app sees the camera
brew install --cask tethercam-obs    # OBS plugin
```

Both are at 0.2.1 (checksums verified 2026-09-10 against the release assets). The Mac app
cask puts `TetherCam.app` into `/Applications` (it has to live there: the camera extension
can only be activated from `/Applications`), needs macOS 14 or newer, and its caveat points
at the one-time approval under System Settings > General > Login Items & Extensions >
Camera Extensions. It carries video only, and the phone serves a single receiver, so the
Mac app and the OBS plugin are not used at the same time.

The sections below are about the OBS plugin cask's shape only.

Decision record for the shape below: `docs/listings/homebrew-decision.md` (see the
"2026-09-06: personal tap live" entry for the audit and install-test results).

The core `homebrew/cask` repo is still out of reach: it needs the repo to be at
least 30 days old and, since this would be a self-submission, 90 forks, 90 watchers or
225 stars (not the lower general-submission numbers). `Kanevry/tethercam` was created
2026-09-05 with 0 stars. The personal tap above is the primary distribution path for
now; revisit core cask much later.

## Install domain: why this is a `zip` cask, not a `pkg` cask

`packaging/distribution.xml.in` sets

```xml
<domains enable_currentUserHome="true" enable_anywhere="false" enable_localSystem="false" />
```

so the `.pkg` installs into the *installing user's* home
(`~/Library/Application Support/obs-studio/plugins/`). A `pkg` stanza in a cask would
make Homebrew run `installer -pkg ... -target /`, which that domain set refuses.
Verify against a real release asset if in doubt:

```sh
installer -pkg TetherCam-obs-plugin.pkg -target / -dumplog
```

Two ways out existed, and this cask deliberately took the second one so the "no admin
rights" promise elsewhere in this repo stays true:

1. Enable `localSystem` in the distribution XML and install into
   `/Library/Application Support/obs-studio/plugins/`. Works for every user on the
   machine, needs an admin password, and changes the uninstall path. **Not taken.**
2. Keep the per-user `.pkg` as the primary install path (`scripts/install.sh`, the
   forum listing, the README) and give the cask its own `zip` artefact instead: an
   `artifact` stanza copies the `.plugin` bundle straight into
   `~/Library/Application Support/obs-studio/plugins/obs-iphone-usb-cam.plugin`,
   exactly where the pkg would have put it, without ever calling `installer -target /`.
   **Taken**, see `tethercam-obs.rb`.

The zip's top-level entry is the bundle itself, not a wrapping folder named after the
zip: `packaging/build-pkg.sh` builds it with `ditto -c -k --keepParent`, and
`--keepParent` on a single bundle argument keeps only that bundle's own directory name.
Verified 2026-09-05 both by reading that script and with a local
`ditto --keepParent` test. That is why the `artifact` stanza's source path is the bare
`obs-iphone-usb-cam.plugin`, not `TetherCam-obs-plugin/obs-iphone-usb-cam.plugin`.

## The tap

A tap is a plain Git repo named `homebrew-<tap>`. `Kanevry/homebrew-tethercam` holds
the cask at `Casks/tethercam-obs.rb` (no letter-sharding: that shard-by-first-letter
layout is a `homebrew/cask` core-tap convention, not required for a personal tap).

`Kanevry/homebrew-tethercam` holds the Mac app cask at `Casks/tethercam.rb` next to it.

Bumping both casks on a new release, the OBS one from the **zip** asset (not the pkg):

```sh
VERSION=X.Y.Z
curl -sL https://github.com/Kanevry/tethercam/releases/download/v$VERSION/TetherCam-obs-plugin.zip | shasum -a 256
curl -sL https://github.com/Kanevry/tethercam/releases/download/v$VERSION/TetherCam-mac.dmg | shasum -a 256
# paste into sha256, bump version in both files, commit + push in the tap repo,
# and mirror the same change back into packaging/homebrew/ here
```

Verify locally before pushing:

```sh
brew tap kanevry/tethercam
brew audit --cask --online kanevry/tethercam/tethercam-obs kanevry/tethercam/tethercam
brew style --cask kanevry/tethercam/tethercam-obs kanevry/tethercam/tethercam
brew install --cask kanevry/tethercam/tethercam-obs
brew uninstall --cask tethercam-obs
```

The release job does not currently bump `version`/`sha256` automatically; each release
needs a manual tap update for **both** casks, otherwise they silently rot one release
behind.
