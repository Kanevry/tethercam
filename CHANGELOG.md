# Changelog

All notable changes to TetherCam are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The repository ships two artefacts with one shared version number: the macOS OBS
plugin (`obs-plugin/`, GPL-2.0-or-later) and the iOS app (`ios-app/`, MIT). A tag
`vX.Y.Z` releases both.

## [Unreleased]

### Added

- **IUCM wire protocol** (`protocol/PROTOCOL.md`) as the contract between both sides:
  framing, message types (CONFIG, VIDEO, PING/PONG), error codes.
- **Shared C core** (`shared/`, MIT): incremental frame parser and usbmux client,
  free of Apple frameworks so it builds and unit-tests on Linux. Covered by ctest,
  including fuzz tests for the frame parser and the usbmux plist reader.
- **iOS app** (`ios-app/`, SwiftUI): AVFoundation capture, hardware HEVC encoding via
  VideoToolbox, TCP listener on port 7878 reachable from the Mac through the usbmux
  tunnel. No Wi-Fi involved.
- **OBS source plugin** "iPhone USB Camera" (`obs-plugin/`, C/ObjC++): connects over
  usbmuxd, decodes HEVC with VideoToolbox, delivers NV12 frames as an async source.
  Universal binary (arm64 + x86_64), Hardened Runtime, macOS 12.0+.
- **Auto-rotation**: the app levels to the horizon via `AVCaptureDevice.RotationCoordinator`
  with gravity-based hysteresis and a flat-device fallback; geometry changes rebuild the
  encoder session and emit a fresh CONFIG. The plugin's Rotation property stays as the
  manual override.
- **Developer tools** (`tools/`, Swift package): `usbcam-sim` (test-pattern sender),
  `usbcam-recv` (CLI receiver over TCP or the usbmux tunnel), and `integration.sh`,
  an end-to-end acceptance run that needs no iPhone.
- **Release engineering**: signed and notarized `.pkg` installer, one-line installer
  script, TestFlight upload workflow, GitHub Actions CI.

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

<!--
Placeholder for the 0.1.0 section. Deliberately NOT written as a "## [0.1.0]" heading:
scripts/changelog-section.py matches headings by regex and does not skip HTML comments,
so a commented-out heading would be extracted as if it were real release notes.

Placeholder only. `scripts/release.sh 0.1.0` promotes the Unreleased section above
into a dated `[0.1.0]` heading and leaves a fresh empty Unreleased in its place.
Do not fill this in by hand: `scripts/changelog-section.py` reads the real heading,
and the release workflow publishes whatever it finds there.
-->

[Unreleased]: https://github.com/Kanevry/tethercam/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kanevry/tethercam/releases/tag/v0.1.0
