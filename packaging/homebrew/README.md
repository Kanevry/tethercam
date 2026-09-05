# Homebrew cask (draft)

`tethercam-obs.rb` installs the released `TetherCam-obs-plugin.zip` from GitHub
Releases. **It is an unpublished draft. Do not link to it, do not document
`brew install` anywhere user-facing yet.** Decision record for the shape below:
`docs/listings/homebrew-decision.md`.

Two things are false today and both must become true before publishing:

1. **The tap does not exist.** There is no `Kanevry/homebrew-tethercam` repository.
   `brew tap kanevry/tethercam` fails. Creating it is a deliberate decision (a tap is
   a maintenance commitment, one more thing that rots per release), not a chore to be
   done in passing.
2. **The checksum is a placeholder** (`0000...`), so the cask cannot install anything.

The core `homebrew/cask` repo is out of reach regardless: it needs the repo to be at
least 30 days old and, since this would be a self-submission, 90 forks, 90 watchers or
225 stars (not the lower general-submission numbers). `Kanevry/tethercam` was created
2026-09-05 with 0 stars. Ship the own tap first; revisit core cask much later.

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

## Publishing a tap

A tap is a plain Git repo named `homebrew-<tap>`. For `brew install --cask kanevry/tethercam/tethercam-obs`:

1. Create the repo `Kanevry/homebrew-tethercam` on GitHub. It does not exist yet;
   every command in this section fails until it does.
2. Put the cask at `Casks/t/tethercam-obs.rb` (Homebrew shards by first letter).
3. Fill in the real values, from the **zip** asset (not the pkg):
   ```sh
   VERSION=0.1.0
   shasum -a 256 TetherCam-obs-plugin.zip   # paste into sha256
   ```
4. Check it locally before pushing:
   ```sh
   brew tap kanevry/tethercam https://github.com/Kanevry/homebrew-tethercam
   brew audit --cask --online kanevry/tethercam/tethercam-obs
   brew install --cask kanevry/tethercam/tethercam-obs
   brew uninstall --cask tethercam-obs
   ```
5. Wire the release job to bump `version` and `sha256` on every tag, otherwise the
   cask silently rots one release behind.

Do not publish before v0.1.0 ships **signed and notarized** (current blocker: the
missing Developer ID Installer certificate, `docs/RELEASING.md` step 1b). An unsigned
`.plugin` bundle fails Gatekeeper for every installer, `brew` included, and
`brew audit --cask --online` flags it.
