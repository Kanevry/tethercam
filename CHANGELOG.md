# Changelog

All notable changes to TetherCam are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The repository ships three artefacts with one shared version number: the macOS app
with the virtual camera (`mac-app/`, MIT), the iOS app (`ios-app/`, MIT) and the macOS
OBS plugin (`obs-plugin/`, GPL-2.0-or-later). A tag `vX.Y.Z` releases them together.

## [Unreleased]

## [0.4.0] - 2026-09-10

### Added

- **Mac app: the camera extension can be restarted from the menu.** After an install
  or an update of the camera extension the app now waits up to 10 seconds for the
  camera device to appear. If macOS started no device — the known launchd race on an
  in-place extension replacement, where the new job is rejected with `EALREADY` while
  the old one is still being torn down — the menu and the setup guide say so instead
  of showing a camera that does not exist, and offer "Restart camera extension"
  (deactivate, then activate again). The presence of the device is re-checked every
  time the menu opens, and the new transient state "Checking the camera device…"
  makes the wait visible. (#32)
- **Mac app: update check.** Once a day at launch the app asks
  `api.github.com/repos/.../releases/latest` whether a newer version exists; the menu
  then shows "Update available: x.y.z" with a link to the release. Settings gain
  "Check for updates now" and a switch "Check for updates automatically", the check
  is off in headless runs, and only `https://github.com` release URLs are ever
  opened. The privacy page names the request. (#27)

### Changed

- **Mac app: the menu is structured.** Status block, Setup guide, the submenus
  "Camera extension" and "Settings", the version, Quit — instead of one flat list.
- **Mac app: the sink authorization stays open, on purpose.** Measured with a
  Developer ID build that `CMIOExtensionClient.signingID` is unusable (it reads
  "unknown" for a real client), so a whitelist would lock every app out of the
  camera. The open policy is kept and documented in the CMIO spec; the extension
  logs the sink client once per pid so the decision stays checkable. (#28)
- Website (EN/DE), README, install guide, `llms.txt` and the App Store metadata got a
  second messaging round: "Your iPhone, instead of a webcam", two apps, one cable.
  (#31)
- Community listings round 2 for the Mac app, store copy at 0.4.0. The iPhone app has
  no code change in this release. (#30)

### Fixed

- **Receiver names longer than 63 bytes no longer break the `CLIENT_INFO` parse.**
  The parser stores 63 bytes plus a terminator; a longer name is now cut at a UTF-8
  character boundary instead of in the middle of a multi-byte character, so the
  phone never shows a mangled receiver name. The fuzz test covers `CLIENT_INFO`.
  (#25)
- **Mac app: cancelling the macOS confirmation dialog is not an error.** Dismissing
  the system prompt for the camera extension reported a failure with code 11; the
  cancel is now recognised and the previous state restored. (#25)

## [0.3.0] - 2026-09-10

### Added

- **Mac app 0.3.0: setup guide, app icon, DMG, login item.** First launch (and any
  launch while the camera extension is not approved) opens a setup guide with four
  steps and live checkmarks: app in /Applications, extension approved (button opens the
  System Settings pane), iPhone connected, camera picked. Notes name the two limits
  (video only, one receiver at a time) and the fix for a camera missing in Zoom or
  Teams: quit the app with Cmd-Q and reopen it, and after an extension install or
  update restart the Mac. The app has an icon, the `.dmg` opens with a drag-to-
  Applications layout, the menu gains About with the version, Launch at Login and
  Remove camera extension. (#20, #13)
- **Mac app: honest counters.** The menu says "Camera ready, no app is reading it yet"
  instead of a rising drop count while nothing consumes the camera; scaler pool drops
  are counted; the extension logs state changes at notice level, and the README has
  the `log stream` recipe. (#16)
- **Zoom and Microsoft Teams verified** with a real iPhone 15 Pro Max on 2026-09-10:
  both list the camera "TetherCam" after a fresh start of the app. The model name of
  the virtual camera is now "TetherCam Virtual Camera". (#13)
- **Plugin and Mac app identify themselves** to the phone with the new `CLIENT_INFO`
  message (protocol 1.2), so the phone's status line names the receiver. (#19)
- CI for the Mac app: `swift test` for the Core package plus an unsigned Release
  build on every push. (#21)
- **iOS 0.3.0: the app knows who is receiving.** Protocol 1.2 adds `CLIENT_INFO`
  (0x04, Mac -> App): the receiver names itself, and the phone's status line says
  "Connected to TetherCam for Mac", "Connected to OBS" or the receiver's own name
  instead of always claiming OBS. The waiting line is now "Waiting for the Mac",
  the first-run hint names both paths (the TetherCam Mac app, which shows up as
  the camera "TetherCam" in Zoom, Teams, Meet and FaceTime, and OBS with the
  TetherCam plugin), and the settings footer links to both downloads. (#19)
- iOS: a second receiver that is turned away with `ERROR 1 BUSY` now says so on
  the phone for five seconds ("Another receiver is already connected"), instead of
  leaving the second Mac black with no explanation. (#19)
- iOS: a "Receiver" row in the diagnostics section with the receiver's name and
  version, or an em dash for a 1.0/1.1 receiver that never identified itself. (#19)

### Changed

- **Positioning: the Mac app is the default path, OBS the pro path.** Website (EN/DE),
  README, install guide, `llms.txt`, App Store metadata 0.3.0 and the store's first
  frame present TetherCam as a wired Mac webcam for Zoom, Teams, Meet and FaceTime,
  with the OBS plugin for streaming, recording and audio. (#22, #23)
- iOS: the microphone footnote follows the receiver. The Mac app carries no audio
  (a CoreMediaIO camera extension has no audio stream), so it now points at the
  Mac's own microphone or the OBS plugin instead of promising sound that cannot
  arrive. (#19)

### Fixed

- iOS: "Auto rotation" and the manual angle survive a relaunch. Both were
  in-memory only, so a mount that needed a fixed angle had to be set up again on
  every start; they now persist like "Level the horizon". (#19)
- iOS: the German microphone purpose string was missing, so the German system
  prompt asked for the microphone in English. (#19)

## [0.2.1] - 2026-09-09

### Added

- **macOS virtual camera (`mac-app/`, MIT).** A menu bar host app embeds a
  CoreMediaIO Camera Extension that publishes the iPhone as the system camera "TetherCam"
  (1920x1080 NV12 30 fps) for Zoom, Teams, FaceTime, browsers and ffmpeg; the host receives
  over usbmux like the plugin, decodes with VideoToolbox, letterboxes every geometry into
  the one format and pushes into the extension's sink stream with host-clock timestamps.
  `--headless` and `--debug-tcp` flags, `scripts/install-local.sh` for the developer
  install. Video only (a camera extension carries no audio); the phone serves one receiver,
  so the Mac app and the OBS plugin are not used at the same time. Verified on 2026-09-09
  with a real iPhone 15 Pro Max in QuickTime Player, Photo Booth, FaceTime, Google Meet
  (Chrome), Safari, Chrome and ffmpeg, portrait and landscape, reconnect after an app
  restart. Ships as the Developer ID signed and notarized `TetherCam-mac.dmg` on the
  GitHub release (`scripts/mac-app-release.sh`); drag to Applications, open, approve the
  camera extension once in System Settings, then pick "TetherCam" in any app. (#12, #13, #14)
- `tools/vcam-test.sh`: end to end check of the virtual camera without a phone
  (`usbcam-sim` → host app headless → ffmpeg avfoundation capture → resolution, fps and
  motion assertions, optional browser `getUserMedia` via `VCAM_BROWSER=1`). Verified
  green on 2026-09-09 with the extension approved: 1920x1080, 30.3 fps, Chrome lists the
  camera.

### Fixed

- **Plugin: black source with the App Store app 0.1.0.** Plugin 0.2.0 sent the 12-byte
  START (audio wish) to every phone; the shipped 1.0 app drops it as a decode error and
  never starts the camera, so OBS showed a black source with no error. The audio bit is
  now only sent when HELLO announces protocol 1.1 or later; against a 1.0 app the plugin
  logs "audio needs 1.1, starting video only" and streams video. `usbcam-recv` gates the
  same way and fails after 8 s without CONFIG instead of hanging on STATS. PROTOCOL.md 4.2
  carries the dated note. Found with the real device on 2026-09-09.
- iOS: a message the parser frames but cannot decode is now logged
  (`[usbcam] dropped undecodable message`) instead of vanishing silently.
- iOS: switching the camera decides on the session queue, so a lens change during a take
  no longer races the capture session's format selection. (#11)

## [0.2.0] - 2026-09-09

### Added

- **Audio from the phone.** The app captures the microphone, encodes AAC-LC 48 kHz mono
  (96 kbps) and sends it on the same cable; the plugin decodes with AudioToolbox and hands
  the samples to OBS (`obs_source_output_audio`), so the source shows up in the audio mixer
  like any other. Protocol 1.1 adds `AUDIO_CONFIG` (0x13), `AUDIO` (0x14), an audio flag in
  START, `MIC_DENIED` (error 6) and STATS bits for audio active/muted; 1.0 receivers keep
  working and simply get no audio.
- **Mute switch** in the app's settings sheet (frame gate, the pts chain stays monotone), a
  `mic.slash` badge in the status capsule while muted, and a microphone-denied state.
- **Plugin property "Audio from the phone"** (default on) and the status line reports the
  audio rate, mute and a denied microphone.
- `usbcam-sim` sends a 440 Hz AAC tone, `usbcam-recv` decodes and counts it
  (`audio_frames`, `audio_video_pts_skew_ms`, `--dump-audio` as ADTS) and
  `tools/integration.sh` asserts the audio path.
- **Double-tap the preview to switch the camera.** The next lens in list order (wide,
  ultra wide, telephoto, front), a short capsule names it, a light haptic confirms it, and
  the choice persists like a pick in Settings. Works during a take: the server swaps the
  lens and OBS gets a fresh CONFIG. (#9, user request after the App Store launch)
- **Homebrew tap**: `brew tap kanevry/tethercam && brew install --cask tethercam-obs`
  copies the plugin bundle into the user's own OBS plugin folder, no admin rights.

### Changed

- The plugin keeps the link on non-fatal peer errors (only BUSY and VERSION_UNSUPPORTED
  disconnect); before, a denied microphone caused an endless reconnect loop without picture.
- iOS build number 4 for the 0.2.0 upload (build 2 is the one on the App Store, 3 was never uploaded).
- The iOS app is on the App Store since 2026-09-09 (0.1.0 approved on the first submission);
  README and website point at the store, TestFlight stays the pre-release channel.
- Repository ships `.env.example` for the App Store Connect API variables.

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
- **iPhone app: camera switching while streaming** no longer stops and restarts the stream.
  The capture session swaps the lens or camera in a single configuration transaction and
  re-applies the last capture angle on the fresh input.
- **iPhone app: localized camera names** in the camera picker (English/German); the names
  sent over the wire protocol stay English so the OBS side is unaffected.
- **OBS plugin: two new link states**, "incompatible" (the phone app uses an unsupported
  protocol version) and "busy" (another receiver is already connected to the phone), each
  with its own status message.
- **Website**: an `/install` guide with a troubleshooting FAQ, a `/changelog` page, and a full
  German landing page at `/de/` (with `hreflang` links for en/de/x-default), plus
  release-aware download labels that query the GitHub releases API.

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


- The App Preview video was withdrawn from the listing (it showed the owner). 0.1.0 ships
  without an App Preview.
- **OBS plugin: connection deadlines.** A 5 second timeout from connect to HELLO and another
  from HELLO to CONFIG make the plugin reconnect instead of hanging indefinitely in
  "Starting" when a phone connection stalls.
- **OBS plugin: quieter logging.** The "no USB device attached" line is throttled to once
  every 30 seconds, and each retry now issues one usbmuxd query instead of several.
- **OBS plugin: fewer decoder rebuilds.** An identical CONFIG message (for example after a
  camera switch that does not change geometry) keeps the existing decoder session instead of
  tearing it down and rebuilding it.
- **OBS plugin: first-run hint.** The Tools-menu hint about adding the TetherCam source now
  also fires when the active scene collection changes, not only at OBS startup. The hint text
  moved into the plugin's locale files and is available in English and German, both pointing
  at https://tethercam.app/#quick-start.
- Store listing docs in `docs/listings/` corrected against verified channel rules; the
  Homebrew cask draft now packages a zip artifact instead of the raw plugin bundle
  (see `docs/listings/homebrew-decision.md`).

### Fixed

- **iPhone app: camera switch could transpose the next frame's orientation.** Switching the
  camera while streaming could send a CONFIG message with the wrong rotation and briefly drop
  to a 720p preview; the encoder now keeps the correct capture angle across the switch and
  skips the preview drop when a restart is already queued.
- **iPhone app: failed camera switch left the capture session inconsistent.** A camera switch
  that fails now restores the previous input, or clears the current input, instead of leaving
  stale state behind.
- **OBS plugin: socket warnings now include the errno text**, making connection failures
  easier to diagnose from the OBS log.

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


[Unreleased]: https://github.com/Kanevry/tethercam/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Kanevry/tethercam/releases/tag/v0.2.1
[0.2.0]: https://github.com/Kanevry/tethercam/releases/tag/v0.2.0
[0.1.0]: https://github.com/Kanevry/tethercam/releases/tag/v0.1.0

