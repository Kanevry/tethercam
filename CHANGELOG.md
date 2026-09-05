# Changelog

All notable changes to TetherCam are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The repository ships two artefacts with one shared version number: the macOS OBS
plugin (`obs-plugin/`, GPL-2.0-or-later) and the iOS app (`ios-app/`, MIT). A tag
`vX.Y.Z` releases both.

## [Unreleased]

### Added

- **App Store submission of 0.1.0 (2)** on 2026-09-05: listing in en-US and de-DE pushed with
  `scripts/asc-listing.py`, five marketing screenshots designed in `tethercam.pen`
  (AI-generated studio scene, no people), TestFlight external group `Public Beta` with the
  public link https://testflight.apple.com/join/wmT74Ry8, Beta App Review and App Review both
  submitted.
- **Local release tooling**: `scripts/appstore-upload.sh` (archive + upload with the App Store
  Connect API key), `scripts/asc-api.sh` (JWT helper), `.claude/skills/distribute`.
- **Website**: demo video embedded with poster, gallery carousel of the App Store frames,
  TestFlight button, FAQ answers for the USB and Continuity Camera queries, VideoObject schema,
  `llms.txt` discoverable.

### Changed

- The App Preview video was withdrawn from the listing (it showed the owner). 0.1.0 ships
  without an App Preview.

## [0.1.0] - 2026-09-05

### Added

- **Tools menu entry** "TetherCam: Add iPhone camera to current scene" (obs-frontend-api,
  no Qt): creates the source in the current scene, names it `TetherCam iPhone`, fits it to
  the canvas (`OBS_BOUNDS_SCALE_INNER`) and does nothing if the scene already has one.
  Removes the step where a first-time user has to find the right entry in the source list.
- **First-run hint**: if no scene in the collection contains a TetherCam source, the plugin
  logs the Tools-menu path once per scene collection at `FINISHED_LOADING` (flag persisted
  in `obs_module_config_path`). Log only, because a dialog would pull in Qt.
- **Status line in the source properties**: read-only first row saying whether a phone is
  attached, whether the app is in the foreground, and the live format plus measured frame
  rate while streaming. Plus a plain-text link to the setup guide.
- **German plugin locale** (`data/locale/de-DE.ini`).
- **German and English app localisation** (`ios-app/Sources/Resources/{de,en}.lproj`),
  including the Info.plist purpose strings.
- **Homebrew cask draft** (`packaging/homebrew/`), unpublished, with the open question about
  the install domain written down.
- **README quick start**: three numbered steps at the top, before the background story.
- **Website https://tethercam.app** as the user-facing entry point: quick start, the
  three-step setup and the download link. The OBS plugin's Help link, the iOS app's
  in-app link and `buildspec.json` all point there now instead of at a repository URL.
- **Public GitHub repository** `Kanevry/tethercam`: the mirror is now the release host,
  with `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, issue templates and a
  pull-request template.
- **README rewritten** around real screenshots of the app and of OBS instead of prose.
- **Diagnostics and advanced-settings screenshots** (`docs/images/app-diagnostics.png`,
  `docs/images/app-settings-advanced.png`) in the README Troubleshooting and Usage sections.
- **IUCM wire protocol** (`protocol/PROTOCOL.md`) as the contract between both sides:
  framing, message types (CONFIG, VIDEO, PING/PONG), error codes.
- **Shared C core** (`shared/`, MIT): incremental frame parser and usbmux client,
  free of Apple frameworks so it builds and unit-tests on Linux. Covered by ctest,
  including fuzz tests for the frame parser and the usbmux plist reader.
- **iOS app** (`ios-app/`, SwiftUI): AVFoundation capture, hardware HEVC encoding via
  VideoToolbox, TCP listener on port 7878 reachable from the Mac through the usbmux
  tunnel. No Wi-Fi involved.
- **OBS source plugin** "TetherCam (iPhone via USB)" (`obs-plugin/`, C/ObjC++): connects over
  usbmuxd, decodes HEVC with VideoToolbox, delivers NV12 frames as an async source.
  Universal binary (arm64 + x86_64), Hardened Runtime, macOS 12.0+.
- **Auto-rotation**: the app levels to the horizon via `AVCaptureDevice.RotationCoordinator`
  with gravity-based hysteresis and a flat-device fallback; geometry changes rebuild the
  encoder session and emit a fresh CONFIG. The plugin's Rotation property stays as the
  manual override.
- **Developer tools** (`tools/`, Swift package): `usbcam-sim` (test-pattern sender),
  `usbcam-recv` (CLI receiver over TCP or the usbmux tunnel), and `integration.sh`,
  an end-to-end acceptance run that needs no iPhone.
- **Release engineering**: installer `.pkg`, signed and notarized when the release is
  built with the Apple signing secrets, otherwise unsigned; one-line installer script,
  TestFlight upload workflow, GitHub Actions CI.
- **Product name TetherCam** and an app icon. The iOS app ships as `TetherCam`
  (bundle id `at.gotzendorfer.tethercam`, marketing version 0.1.0) with a 1024x1024
  asset-catalog icon; the OBS source is listed as "TetherCam (iPhone via USB)" and
  the plugin display name is "TetherCam for OBS". The internal module name stays
  `obs-iphone-usb-cam` and the source id stays `iphone_usb_camera`.

### Changed

- **Camera names sent to OBS are English** (`Back Wide`, `Back Ultra Wide`, `Back Telephoto`,
  `Front`) instead of German. They travel in HELLO and are shown verbatim in the OBS camera
  property and in the app's settings sheet, so English OBS users no longer see German labels.
- **iOS app reduced to one screen**: full-screen preview with a single status line and a
  traffic-light dot ("Waiting for OBS on the Mac" / "Connected to OBS" / "Streaming 1080p30").
  Camera choice, auto rotation, horizon levelling, manual angle and the diagnostics moved
  behind one gear icon; the camera list is plain rows with a checkmark instead of a picker,
  which was unreadable with four lenses. Keep-screen-on is now always on and no longer a switch.
- **Camera permission** is requested on first launch without an intermediate onboarding page;
  a denial shows a card with a button into Settings.
- **ENABLE_FRONTEND_API** defaults to ON in `obs-plugin/CMakeLists.txt` and the CMake presets.
- **`scripts/install.sh` now points at the right repository** (`OWNER=Kanevry`). The
  previous owner did not exist, so the one-line installer downloaded nothing.
- **TestFlight workflow no longer fails without secrets**: a `check-secrets` job resolves
  `ASC_KEY_P8` presence and the upload job is skipped rather than failed. A tag push in a
  fork, or in this repo before the App Store Connect key is configured, is now green.

### Verified

- 1080p30 over usbmuxd against a physical iPhone.
- `tools/integration.sh` end to end against the simulator: frame rate, keyframe
  cadence, first-frame latency, ping round-trip, and an ffmpeg decode of the dump.

### Known limitations

- macOS only. The plugin depends on VideoToolbox and usbmuxd; the CMake configure
  step fails on other platforms by design.
- One iPhone at a time.
- The iOS app is distributed via TestFlight only. Apple offers no free public
  distribution channel outside the App Store and TestFlight.


[Unreleased]: https://github.com/Kanevry/tethercam/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kanevry/tethercam/releases/tag/v0.1.0
