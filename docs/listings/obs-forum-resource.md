# OBS Resources draft: TetherCam

Venue: https://obsproject.com/forum/resources/. Release information and the
[Forum Resource and IP Policy](https://obsproject.com/forum/threads/forum-resource-and-ip-policy.178569/)
were checked on 2026-09-09. The field layout and exact category name below were last
checked against live listings on 2026-09-06.

**Status: draft ready for submission, pending forum two-step verification.**
The current policy says: "Resources created or written entirely, or in large part,
with AI coding tools are not permitted." It also requires disclosure of what AI tools
did for code, art and other content; disclosure alone does not establish eligibility.

**Developer attestation, 2026-09-09:** Bernhard states that he wrote the code
predominantly himself and used AI selectively: he made TetherCam with AI assistance;
AI did not make it on its own. This resolves the previously unanswered question about
predominant authorship. The draft follows that attestation and discloses the assistance.
The forum moderation team still makes the final submission decision.

Supporting provenance notes:

- 22 of the 57 commits through `v0.2.0` have a Claude co-author trailer. These include
  iOS/plugin audio implementation (`c02b761`, `58cd69a`, `836cc55`) and camera-switching
  code (`9132136`).
- The foundational shared/iOS/simulator code entered in `b19624e` (6,568 insertions)
  and the OBS plugin in `0430dfe` (4,931 insertions), described as development waves.
  Neither commit has an AI trailer. The history does not establish what fraction of
  that code was AI-written; commit counts are not a measure of code authorship.
- `4b1c135` records an icon generated with `gpt-image-2`; `6d0848f` records the
  AI-generated studio scene used in the Pen marketing frames.
- This description is AI-assisted. The earlier claim that it was written entirely
  by hand was false and has been removed. The co-author trailers document assistance;
  they do not contradict the developer's statement about predominant authorship.

**Before you start:** the forum account needs two-step verification enabled, or "Add
Resource" is not offered. The button sits top right of the resources page once logged
in and verified.

Category: **OBS Studio Plugins** (exact name, confirmed live 2026-09-06; not "Plugins").
Release facts below were checked on 2026-09-09: the Mac plugin is at v0.2.0 and the
public App Store app is at 0.1.0. The iOS 0.2.0 audio update is under review. Re-check
the current forum rules and the submission fields before publishing; the venue notes
above record earlier checks, not a fresh moderation clearance.

**After submitting:** the resource shows status "DELETED" until a moderator approves
it. That is normal moderation queue behaviour, not an error and not an actual deletion.
Do not resubmit or panic if it says that for a day or two.

---

## Fields (as seen on live resource listings)

| Field | Value |
|---|---|
| Title | `TetherCam` (no "OBS" in the name; see policy note below) |
| Version | `0.2.0` |
| Tagline | see below |
| Minimum OBS Studio Version | `30.0` |
| Source code URL | `https://github.com/Kanevry/tethercam/tree/v0.2.0` (the released plugin tag) |
| Platforms | macOS 12+; tested on Apple Silicon |
| Download link ("Go to download") | `https://github.com/Kanevry/tethercam/releases/download/v0.2.0/TetherCam-obs-plugin.pkg` |
| Icon | `docs/images/tethercam-icon-256.png`, 256x256 |
| Description | rich text, see below; prepared with AI assistance |
| Screenshots | gallery, see list below |

## Policy notes specific to this venue

- **No "OBS" in the product name.** The Title field above is `TetherCam`, not
  "TetherCam OBS" or similar. "OBS" only appears in the tagline/description as a
  description of what the plugin is for, never as part of the name.
- **No implied OBS branding.** `docs/images/tethercam-icon-256.png` is the TetherCam
  icon, not an OBS mark. The policy permits application screenshots in third-party
  marketing when the independent relationship is clear.
- **No implied affiliation.** The description below does not claim endorsement by or
  partnership with the OBS Project; it says "for OBS Studio", nothing stronger.
- **GPL compliance** is satisfied by the public source repository: `obs-plugin/` is
  GPL-2.0-or-later (links against libobs) and the repo is public at
  `https://github.com/Kanevry/tethercam`; the Source code URL field above points at it.
  Say so plainly in the description (see License section below).
- **Release-ready only.** The Source code URL and Download link fields both resolve to
  the v0.2.0 tag/release, never to `main` or a branch, so a visitor's first click
  always lands on something installable.
- **English.** All text below is English.
- **AI assistance is disclosed for code, art and copy.** See the developer attestation
  above and the disclosure below. Checking this draft against release information
  does not mean that the owner has personally reviewed it or that the forum permits
  the resource.
- **Repo/bundle name note:** the public repository is `Kanevry/tethercam`; the plugin
  bundle retains the implementation name `obs-iphone-usb-cam.plugin`. The resource
  Title and the user-facing product name are `TetherCam`.

---

## Title

TetherCam

## Tagline (one line)

Use your iPhone as a webcam for OBS Studio over a plain USB cable, no Wi-Fi, no cloud, no pairing screen.

## Description

TetherCam brings the iPhone camera into OBS Studio on macOS through the USB cable. The
phone encodes HEVC in hardware and serves the stream on a local TCP port; the Mac reaches
that port through usbmuxd, the same system service that carries Xcode traffic over the
cable; the plugin decodes with VideoToolbox and hands NV12 frames straight to OBS.
Nothing is buffered in the plugin and nothing leaves the cable. TetherCam is not
affiliated with or endorsed by the OBS Project.

I built it because I kept losing the iPhone connection while recording videos for
Agentic Builders. AirDrop wasn't solving the recording workflow for me either. On my
setup, Continuity Camera's handshake succeeded but the picture stayed black after an
iOS/macOS version mismatch. I wanted a reliable cable path straight into OBS that did
not depend on that handshake. Continuity Camera itself supports USB; TetherCam takes a
separate path through usbmuxd. It is free and open source.

As of September 9, 2026, the Mac plugin is at 0.2.0 and the free iPhone app is available
on the App Store at 0.1.0. That combination delivers video. The iOS 0.2.0 update adds
microphone audio over the same cable and is still under App Review; installing plugin
0.2.0 alone does not add phone audio to the current App Store app. Early builds use the
public TestFlight channel. Please report bugs and feedback as GitHub issues.

1080p30 and 1080p60 have been tested on an iPhone 15 Pro Max with an M4 Pro Mac and
OBS 32.2.2. Results depend on your phone, Mac, cable and settings.

The plugin installs into your own home folder under the OBS plugins directory. No
administrator rights, no system extension, no daemon.

**AI disclosure:** Developed by Bernhard Götzendorfer, with selective AI assistance for
code and documentation. AI tools were also used for the icon and illustrative marketing
artwork. This description was prepared with AI assistance and checked against the release.

## Features

- Video over the USB cable only. No Wi-Fi, no cloud service, no account, no pairing code.
- 1280x720 or 1920x1080 at 30 or 60 fps, bitrate adjustable (default 12000 kbit/s).
- Hardware HEVC encoding on the phone, VideoToolbox decoding on the Mac.
- One menu entry: Tools, then "TetherCam: Add iPhone camera to current scene" creates the
  source and fits it to the canvas.
- Camera and lens picker in the app: Back Wide, Back Ultra Wide, Back Telephoto, Front.
- Auto rotation with horizon leveling on the phone, so OBS receives a picture that is
  already the right way up. Manual 0/90/180/270 override on either side.
- Status line at the top of the source properties that names the missing step when the
  picture is black; matching diagnostics sheet in the app.
- Reconnects on its own after a cable pull.
- Documented wire protocol (`protocol/PROTOCOL.md`) if you want to write your own receiver.
- Open source. Plugin GPL-2.0-or-later, everything else MIT. Source at
  `https://github.com/Kanevry/tethercam`.

## Requirements

- iPhone XR or newer with iOS 17 or later. Tested on iPhone 15 Pro Max, iOS 26.6.1.
- Mac with macOS 12 or later. Tested on macOS 26.5.2, Apple Silicon.
- OBS Studio 30 or later. Tested with 32.2.2.
- A data cable, not a charge-only one.

## Install

**Mac plugin**

1. Download `TetherCam-obs-plugin.pkg` from the v0.2.0 release
   (https://github.com/Kanevry/tethercam/releases/tag/v0.2.0) and open it, or run
   `curl -fsSL https://raw.githubusercontent.com/Kanevry/tethercam/main/scripts/install.sh | bash`.
   Read the script first; it downloads the release bundle and unpacks it into
   `~/Library/Application Support/obs-studio/plugins/`, nothing else.
2. The `.pkg` is signed with a Developer ID Installer certificate and notarized by
   Apple. Restart OBS after installation.

**iPhone app**

1. Install the free App Store app: https://apps.apple.com/us/app/tethercam/id6808997521.
   The public version is 0.1.0 and sends video; the 0.2.0 audio update is under review
   as of September 9, 2026.
2. For early builds, the public TestFlight channel is
   https://testflight.apple.com/join/wmT74Ry8. Available builds can change independently
   of the App Store release.
3. Or build it yourself with a free Apple ID and Xcode; steps in the README under
   "Install the iPhone app".

**Use it**

1. Connect the phone with a data cable and unlock it.
2. Open TetherCam on the phone and leave it in the foreground. The app keeps the screen
   on while streaming; iOS suspends the listener as soon as the app goes to the background.
3. In OBS: Tools, then "TetherCam: Add iPhone camera to current scene". The status line
   on the phone turns green and says "Streaming 1080p30".

## Known limitations

- Early releases; feedback from other phone and Mac setups is welcome.
- macOS only. The shared C core builds on Linux, but no Windows or Linux receiver ships.
- The current App Store app (0.1.0) sends video only. Use a separate microphone in OBS
  until the iOS 0.2.0 audio update is available. Phone audio requires 0.2.0 on both sides.
- HEVC only. The phone encodes HEVC in hardware; there is no H.264 fallback.
- One receiver per phone. A second OBS source or the CLI receiver gets `ERROR 1 BUSY`.
- The app must stay in the foreground on an unlocked phone.
- Plugin only, no virtual camera: the picture shows up in OBS, not in Zoom or FaceTime.
  A CMIO Camera Extension is on the roadmap, not in this release.

## Support and issues

- Issues and bug reports: https://github.com/Kanevry/tethercam/issues
- Source and releases: https://github.com/Kanevry/tethercam
- Website: https://tethercam.app
- Privacy policy: https://tethercam.app/privacy (the app collects no data)

## License

- `obs-plugin/`: GPL-2.0-or-later, because it links against libobs. GPL compliance is
  the public source repository above; the full source at the v0.2.0 tag is what the
  Source code URL field links to.
- iPhone app, shared C core, tools, protocol spec, docs: MIT.

## Icon

`docs/images/tethercam-icon-256.png`, 256x256. Not an OBS logo or a modification of one.

## Screenshots to attach

PNG is the safest format for this venue; WebP support on the forum's upload form is
unconfirmed as of 2026-09-05, so use the PNG originals below rather than the `web/img/*.webp`
twins unless a test upload confirms WebP works.

Upload in this order (repo paths):

1. `docs/images/obs-iphone-live.png`: OBS showing live 1080p from the iPhone.
2. `docs/images/obs-tools-menu.png`: the Tools menu entry.
3. `docs/images/obs-plugin-properties.png`: source properties with the status line.
4. `docs/images/app-live.png`: the app streaming, status capsule "Streaming 1080p30".
5. `docs/images/app-settings-sheet.png`: camera and lens picker, resolution.
6. `docs/images/app-diagnostics.png`: diagnostics sheet on the phone.
7. `docs/images/architecture.svg`: data path diagram (convert to PNG, SVG upload is
   unconfirmed on this venue too).

Demo video, 54 seconds: https://tethercam.app (embedded), file `web/demo.mp4`. Link it
in the description text rather than uploading the raw file if the venue has no video
upload field.
