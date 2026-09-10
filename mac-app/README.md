# TetherCam for macOS

Menu bar host app plus CoreMediaIO Camera Extension. The host receives the HEVC
stream from the iPhone over USB (usbmuxd, TCP 7878), decodes it with VideoToolbox
and feeds the frames into the extension's sink stream; the extension publishes the
iPhone as the camera "TetherCam" (1920x1080, NV12, 30 fps) to every app on the Mac
(Zoom, Teams, FaceTime, ffmpeg, ...). No OBS required.

## Install (users)

Download **[TetherCam-mac.dmg](https://github.com/Kanevry/tethercam/releases/latest/download/TetherCam-mac.dmg)**
(0.3.0, build 9; Developer ID signed, notarized and stapled; macOS 14 or newer,
Apple silicon and Intel; free, MIT). The checksum sits next to it as
`TetherCam-mac.dmg.sha256`. Homebrew works too:
`brew tap kanevry/tethercam && brew install --cask tethercam`.

1. Install TetherCam on the iPhone from the [App Store](https://apps.apple.com/us/app/tethercam/id6808997521) and open it.
2. Plug the iPhone into the Mac with the USB cable, tap **Trust** on the phone the first time.
3. Open the `.dmg` and **drag TetherCam into Applications with Finder**, then open it. It lives in the menu bar and has no window.
4. macOS asks once to allow the camera extension: System Settings > General >
   Login Items & Extensions > Camera Extensions > enable TetherCam (admin
   password once). The menu bar app has a button that opens that pane.
5. In any app pick the camera **TetherCam**: Zoom (camera menu), Google Meet
   (arrow next to the camera button), FaceTime (Video menu), QuickTime Player
   (New Movie Recording, arrow next to the record button), Photo Booth (Camera
   menu), Safari and Chrome (the site's camera picker), Teams (Settings >
   Devices).

On first launch — and whenever the camera extension is not approved — a **setup
guide** window opens with those steps and live checkmarks (in /Applications yes/no,
extension approved yes/no, phone streaming yes/no). Reopen it any time from the menu
bar: **Setup guide…**. It never opens in `--headless` runs.

The menu bar also carries:

- **Launch at Login** — a toggle backed by `SMAppService.mainApp`. If macOS refuses
  (the login item was denied under System Settings > General > Login Items), the menu
  shows a sentence instead of failing silently.
- **Remove camera extension…** — asks for confirmation, then deactivates the camera
  extension (macOS asks once more). Afterwards drag `TetherCam.app` to the Trash.
- **TetherCam 0.3.0 (7)** — the version line, `MARKETING_VERSION (CURRENT_PROJECT_VERSION)`
  read from the bundle. The same version travels to the phone in CLIENT_INFO
  (protocol 1.2), so the iPhone can name the connected receiver.

The camera carries **video only** (a macOS camera extension cannot carry audio),
the output is a fixed 1920x1080 at 30 fps (a portrait phone is pillarboxed), and
the phone serves **one receiver at a time**: run either this app or the OBS
plugin source, not both, or the second one gets BUSY.

Troubleshooting:

- **"Error: TetherCam.app must be in /Applications"** although it is there: the
  app was copied by something other than Finder while it still carried the
  quarantine flag, so macOS App Translocation runs it from a random path. Drag it
  in with Finder, or `xattr -dr com.apple.quarantine /Applications/TetherCam.app`.
- **No "TetherCam" camera in any app:** the extension is not enabled yet (step 4),
  or the app that should show it was launched before the extension appeared — quit
  and reopen it, camera lists are read at launch.
- **BUSY:** another receiver holds the phone; close the OBS TetherCam source first.
- **Nothing arrives:** open TetherCam on the phone and leave it in the foreground,
  iOS suspends the listener in the background.

## Layout (developers)

`Core/` is the SwiftPM package (`TetherCamContract` = identifiers and the
published format, compiled into both targets; `TetherCamCore` = receiver, decoder,
sink bridge). `App/` is the host, `Extension/` the camera extension.

## Build

```bash
cd mac-app
xcodegen generate
xcodebuild -scheme TetherCam -configuration Release \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -derivedDataPath build build CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=G3QZ66475M
# -> build/Build/Products/Release/TetherCam.app
#    (contains Contents/Library/SystemExtensions/at.gotzendorfer.tethercam.mac.camera.systemextension)
cd Core && swift test          # 20 tests incl. the pipeline against usbcam-sim
```

## Install locally (developer Mac)

```bash
swift build --package-path tools -c release --product usbcam-sim   # optional, for tests/headless
bash mac-app/scripts/install-local.sh
```

The script builds Release, copies the app to `/Applications` (replacing only a
bundle whose `CFBundleIdentifier` is `at.gotzendorfer.tethercam.mac`), launches it
once (which submits the extension activation request) and prints the
`systemextensionsctl list` line. `activated waiting for user` means: System
Settings > General > Login Items & Extensions > Camera Extensions > enable
TetherCam; the script opens that pane. Exit codes: `1` when the build product is
missing, `/Applications/TetherCam.app` belongs to another bundle id, or the copy
fails (it prints the `sudo cp` to run); `2` when no activation request was seen
within 20 s (it prints the last sysextd log lines); `0` otherwise, including the
"APPROVAL NEEDED" case, so read the printed state as well.

End to end without a phone: `bash tools/vcam-test.sh` (sim on `IUCM_PORT`,
default 7980; exit 0 PASS (requires pushed>0 in the host status line, so the extension placeholder never passes), 1 FAIL, 3 extension waiting for approval, 4 extension
not registered). Artefacts under `/tmp/vcam-test/`.

## Why /Applications and the System Settings approval

A camera extension is a macOS system extension. `systemextensionsctl` only
activates extensions that are embedded in an app located in `/Applications`
(`OSSystemExtensionErrorUnsupportedParentBundleLocation` otherwise), and the first
activation must be approved by the user under System Settings > General >
Login Items & Extensions > Camera Extensions. TetherCam submits the activation
request on every launch, shows the state in its menu and offers a button that opens
that settings pane. The extension runs sandboxed inside Apple's
`registerassistantservice`; the host is not sandboxed because it talks to
`/var/run/usbmuxd` and TCP sockets just like the OBS plugin does.

## Headless flags

- `--headless`: every pipeline status change is one stderr line:
  `tethercam: link=<state> camera=<status> res=<WxH@fps> fps=<n> received=<n> pushed=<n> dropped=<n> no-consumer=<bool>`
  (`link`: no-device|waiting|starting|streaming|incompatible|busy;
  `camera`: missing|waiting-for-user|ready|error). Tokens are `key=value`, parse by
  key, not by position. Runs until SIGTERM.
- `--debug-tcp HOST:PORT`: connect to a plain TCP source (`usbcam-sim`) instead of
  usbmuxd.
- `--no-activate`: skip the system extension activation request.

```bash
tools/.build/release/usbcam-sim --bind 127.0.0.1 --port 7878 --no-audio &
/Applications/TetherCam.app/Contents/MacOS/TetherCam --debug-tcp 127.0.0.1:7878 --headless
```

`pushed` only grows once the extension is enabled; until then the host keeps
receiving and retries the sink every 2 s. **`dropped` climbing while nothing is
wrong is the normal idle state:** with no app reading the camera the extension
never dequeues, the sink queue stays full, `pushed` freezes at the queue capacity
and every arriving frame is dropped. The host derives that state
(`no-consumer=true`, `PipelineStatus.noConsumer`: `pushed` unchanged for more than
1 s while `fps > 0`) and the menu shows it as a sentence; the raw counters appear
only under `--debug-tcp` / `--headless`. Note that `queue=<n>` is the capacity
CoreMediaIO actually handed over (measured 10 on macOS 26.6), not the
`TetherCamContract.sinkQueueDepth` of 4 the extension requests through
`CMIOExtensionStreamProperties.sinkBufferQueueSize` — the system may grant more.

## Update check

The app asks `api.github.com` for the latest `Kanevry/tethercam` release at most once
per day and shows "Update available: x.y.z" in the menu; the download stays manual
(.dmg or `brew upgrade --cask tethercam`). No telemetry: the request carries nothing
but the GitHub URL and a `TetherCam/<version>` User-Agent, no identifier is sent, no
answer is uploaded anywhere, and `--headless` / `--debug-tcp` runs never check at all.

What leaves the Mac, exactly: one `GET
https://api.github.com/repos/Kanevry/tethercam/releases/latest` with
`Accept: application/vnd.github+json` and `User-Agent: TetherCam/<version>` — at most
once per 24 h, and only when the app is launched.

Off switch: the menu has "Check for updates automatically". Unchecking it stops the
silent daily check; "Check for updates…" still works on demand. It is stored as the
`UserDefaults` boolean `checkForUpdatesAutomatically` in the app's domain (absent = on):

```bash
defaults write at.gotzendorfer.tethercam.mac checkForUpdatesAutomatically -bool false
```

## Sink authorization

Any local client may open the extension's sink stream; the extension logs the client
but does not gate it. A `signingID == at.gotzendorfer.tethercam.mac` gate was measured
twice (2026-09-09 Apple Development, 2026-09-10 Developer ID, macOS 26.6.2) and
`CMIOExtensionClient.signingID` carried no usable value either time, so the gate would
lock out the host itself. Details in
`docs/superpowers/specs/2026-09-09-virtual-camera-cmio.md`.

## Extension logs

The extension runs sandboxed inside `registerassistantservice`, where `Logger.info`
lines are not persisted (`log show --info` returns nothing for them). State changes
are logged at `.notice`, failures at `.error`; per-frame chatter stays at `.debug`.

```bash
log stream --predicate 'subsystem == "at.gotzendorfer.tethercam.mac.camera"' --level notice
# host side (menu bar app):
log stream --predicate 'subsystem == "at.gotzendorfer.tethercam.mac"' --level info
```

`log show --last 10m --predicate '...'` works for the same `.notice` lines after the
fact. Useful markers: `sink started` / `sink stopped`, `source started, clients=N`,
`sink stalled for 1 s, placeholder on`, `sink resumed, placeholder off`. Frame timestamps handed to the extension
are the host clock at push time (`CameraPipeline`), because camera clients expect
host-clock presentation times and the phone clock is unrelated.

## License

MIT (see the repository root). The camera extension and the host contain no OBS code.
