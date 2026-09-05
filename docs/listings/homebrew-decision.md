# Homebrew: cask decision memo

Not a draft to post anywhere. Decision record for whether/how to ship a Homebrew cask.

## Facts (verified 2026-09-05)

- `homebrew/cask` (the core tap) requires 30 forks, 30 watchers or 75 stars to accept a
  cask, but a project's own maintainer submitting their own cask needs three times that:
  90 forks, 90 watchers or 225 stars. TetherCam would be a self-submission.
- A repository younger than 30 days is ineligible outright, independent of stars.
  `Kanevry/tethercam` was created 2026-09-05 (today) with 0 stars: fails both the age
  gate and the star count by a wide margin.
- Cask artifacts must pass Gatekeeper. `TetherCam-obs-plugin.pkg` is unsigned until the
  Developer ID Installer certificate exists (see `docs/RELEASING.md` 1b); an unsigned,
  unnotarized `.pkg` fails `brew audit --cask --online` and fails for users at install.
- `brew install --cask` with a `pkg` stanza runs `installer -pkg ... -target /`. Our
  `.pkg` payload only enables `currentUserHome` (`packaging/distribution.xml.in`:
  `enable_localSystem="false" enable_currentUserHome="true"`), so that installer call is
  refused: `-target /` needs `localSystem`, which we deliberately do not enable.

## Options

1. **Flip `enable_localSystem` to true.** Installs machine-wide, works with `pkg` +
   `-target /` unmodified. Breaks the "no admin rights" promise this project makes
   everywhere else (README, forum listing, site).
2. **Cask with a `zip` artifact instead of `pkg`.** Homebrew unzips (no `installer`
   call, no Gatekeeper install-domain problem) and an `artifact` stanza copies the
   `.plugin` bundle straight into the user's own OBS plugins folder. Keeps the no-admin
   promise; Homebrew is only doing what `scripts/install.sh` already does by hand.
3. **Wait.** Do nothing until the repo is old enough and popular enough, and the `.pkg`
   is signed.

## Recommendation

Personal tap first: `Kanevry/homebrew-tethercam`, cask built as **option 2** (zip
artifact, no admin rights needed), and only once v0.1.0 ships signed and notarized
(current blocker: the missing Developer ID Installer certificate, `docs/RELEASING.md`
1b). A personal tap has no age or popularity gate.

The core `homebrew/cask` submission is not worth attempting before the repo clears
**both** the 30-day age floor and the self-submission thresholds above (90 forks, 90
watchers or 225 stars, whichever comes first), not the lower general-submission
numbers, since this would be a self-submission. Revisit this memo once those numbers
are close.

`packaging/homebrew/tethercam-obs.rb` is updated to the option-2 shape; see
`packaging/homebrew/README.md` for the checksum layout that shape needs and why the
`artifact` path in the cask is the bare `.plugin` bundle name, not a wrapping folder
(verified against `packaging/build-pkg.sh`'s `ditto --keepParent` call). The cask
remains untested end to end: no signed release exists yet to install from.
