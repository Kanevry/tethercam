# Homebrew cask (draft)

`tethercam-obs.rb` installs the released `TetherCam-obs-plugin.pkg` from GitHub
Releases. It is **not published**: no tap exists yet and the checksum in the file
is a placeholder.

## Blocker before publishing

This cask cannot work as written yet, and the reason is in this repo:
`packaging/distribution.xml.in` sets

```xml
<domains enable_currentUserHome="true" enable_anywhere="false" enable_localSystem="false" />
```

so the pkg installs into the *installing user's* home
(`~/Library/Application Support/obs-studio/plugins/`). Homebrew runs
`installer -pkg ... -target /`, which that domain set refuses. Verify against a
real release asset:

```sh
installer -pkg TetherCam-obs-plugin.pkg -target / -dumplog
```

Two ways out, both a deliberate decision, not a detail:

1. Enable `localSystem` in the distribution XML and install into
   `/Library/Application Support/obs-studio/plugins/`. That works for every user
   on the machine, needs an admin password, and changes the uninstall path.
2. Keep the per-user pkg and drop the `pkg` stanza for a `zip` artefact plus an
   `artifact` stanza pointing at the plugin folder in the user's home.

Do not publish before this is settled. A cask that installs but cannot uninstall
is worse than no cask.

## Publishing a tap

A tap is a plain Git repo named `homebrew-<tap>`. For `brew install --cask kanevry/tethercam/tethercam-obs`:

1. Create the repo `Kanevry/homebrew-tethercam` on GitHub.
2. Put the cask at `Casks/t/tethercam-obs.rb` (Homebrew shards by first letter).
3. Fill in the real values:
   ```sh
   VERSION=0.1.0
   shasum -a 256 TetherCam-obs-plugin.pkg   # paste into sha256
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

The core `homebrew/cask` repo is a separate question: it requires a notarized
package and a project with visible usage. Ship the own tap first.
