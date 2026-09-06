# awesome-obs PR draft

Target: https://github.com/Pralhad-Nasane/awesome-obs (verified maintained, last push
2026-08-17, on 2026-09-05). Section `## Plugins` > `### Camera & Video Sources`. Entry
format verified against the live `README.md` on `main`: `- [Name](link) - Description.`
one-liners, description starts with a capital letter, ends with a period, does not
start with "A"/"An", does not repeat the name, about 80 characters max, list kept
alphabetical, one PR per suggestion. It has a `CONTRIBUTING.md`; read it before opening
the PR. The list already carries the prior art in the same section:

```
- [iOS Camera Source](https://github.com/wtsnz/obs-ios-camera-source) - High-quality H.264 video streaming from iPhone cameras over USB.
```

Place the TetherCam line directly after that entry: alphabetically "TetherCam" sorts
after "iOS Camera Source" anyway (case-insensitive i < t), and it puts the two USB
approaches together.

The larger `streamgeeks/Awesome-OBS-Plugin-List` is a prose guide, not an awesome-format
list, has no one-line entry format, and has been stale since 2021. Do not reference it
in the PR or use it as a format example.

Do not open the PR before the v0.1.0 GitHub release is published (see `README.md` in this
folder).

## Entry (exact line)

```
- [TetherCam](https://github.com/Kanevry/tethercam) - Wired iPhone camera for OBS over USB with hardware HEVC and no Wi-Fi or pairing.
```

Section: `## Plugins` > `### Camera & Video Sources`. Description is 80 characters,
starts with a capital letter, ends with a period, does not start with "A"/"An", does
not repeat "TetherCam".

## Before opening the PR

```
npx awesome-lint README.md
```

Run this against the forked `README.md` with the entry added, from the repo root of the
fork. Fix anything it flags before opening the PR; a failing lint is the fastest way to
get a PR closed unread on an awesome-list.

## PR title (includes link and reason)

```
Add TetherCam (github.com/Kanevry/tethercam) to Camera & Video Sources: wired USB alternative to Continuity Camera
```

## PR description

```
Adds TetherCam, an open-source macOS plugin plus iPhone app that brings the iPhone camera into OBS over the USB cable (HEVC in hardware on the phone, VideoToolbox in the plugin, no Wi-Fi). First release v0.1.0 published <RELEASE_DATE>: <RELEASE_URL>. I am the author; placed next to iOS Camera Source since both use the USB path. `npx awesome-lint README.md` passes locally.
```

## Placeholders

- `<RELEASE_DATE>`: v0.1.0 release date.
- `<RELEASE_URL>`: v0.1.0 release page.

## 2026-09-06: PR opened

- PR: https://github.com/Pralhad-Nasane/awesome-obs/pull/10 (fork `Kanevry/awesome-obs`, branch
  `add-tethercam`, commit "Add TetherCam"), body follows the repo's
  `.github/pull_request_template.md` with every checklist item ticked.
- Placement as planned, directly after "iOS Camera Source". Two premises of this draft were
  wrong in practice: the guidelines file is `contributing.md` (lowercase), and the
  "Camera & Video Sources" section is not alphabetical (DroidCam, RemoteCam, Spout2, OBS Kinect,
  iOS Camera Source, OpenVR Input). Thematic placement next to the other USB approach stands.
- `npx awesome-lint README.md` on the branch and on `main` of the fork report the identical two
  errors (missing `awesome` / `awesome-list` GitHub topics, which forks do not inherit); the
  entry adds zero new lint findings. Upstream carries the topics, so upstream CI is unaffected.
- Next: watch the PR for maintainer feedback; amend the commit if the maintainer asks for wording
  changes (see contributing.md "Updating your Pull Request").
