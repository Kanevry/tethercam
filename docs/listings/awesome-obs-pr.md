# awesome-obs PR draft

Target list: https://github.com/Pralhad-Nasane/awesome-obs (format verified 2026-09-05
against the raw README on `main`: awesome.re badge, `- [Name](url) - Description.` one-liners,
section `### Camera & Video Sources` under `## Plugins`). It has a `contributing.md`; read it
before opening the PR. The list already carries the prior art in the same section:

```
- [iOS Camera Source](https://github.com/wtsnz/obs-ios-camera-source) - High-quality H.264 video streaming from iPhone cameras over USB.
```

Place the TetherCam line directly after that entry so the two USB approaches sit together.

The larger `streamgeeks/Awesome-OBS-Plugin-List` (143 stars) is a prose guide, not an
awesome-format list, and has no one-line entry format; skip it.

Do not open the PR before the v0.1.0 GitHub release is published (see `README.md` in this
folder).

## Entry (exact line)

```
- [TetherCam](https://github.com/Kanevry/tethercam) - iPhone as an OBS camera over the USB cable on macOS. Hardware HEVC on the phone, VideoToolbox decode in the plugin, no Wi-Fi and no cloud. Open source, GPL-2.0 plugin, MIT app.
```

Section: `## Plugins` > `### Camera & Video Sources`.

## PR title

```
Add TetherCam to Camera & Video Sources
```

## PR description (3 lines)

```
Adds TetherCam, an open-source macOS plugin plus iPhone app that brings the iPhone camera into OBS over the USB cable (HEVC in hardware on the phone, VideoToolbox in the plugin, no Wi-Fi). First release v0.1.0 published <RELEASE_DATE>: <RELEASE_URL>. I am the author; placed next to iOS Camera Source since both use the USB path.
```

## Placeholders

- `<RELEASE_DATE>`: v0.1.0 release date.
- `<RELEASE_URL>`: v0.1.0 release page.
