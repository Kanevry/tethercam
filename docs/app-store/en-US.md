# App Store metadata: English (U.S.), primary localization

Version 0.3.0, build 6. Bundle id `at.gotzendorfer.tethercam`. Free. iPhone only, landscape
only, iOS 17+. Source of the wording: `docs/APP-STORE-RELEASE.md` sections 4.1 to 4.6.
Every fenced block below is meant to be pasted verbatim into the matching App Store Connect
field. Character limits are checked by `docs/app-store/validate.sh`.

---

## Name (limit 30)

```
TetherCam
```

## Subtitle (limit 30)

```
iPhone webcam over USB cable
```

## Keywords (limit 100)

```
tether,wired,camcorder,streaming,capture,meeting,conference,call,video,live,studio,cam,mic,obs,mac
```

Comma separated, no spaces after commas, 98 of 100 characters. Words from the name and the
subtitle are not repeated; Apple indexes those already, which is why `iphone`, `usb`,
`webcam` and `cable` do not appear here: the subtitle "iPhone webcam over USB cable"
carries all four. Because that subtitle no longer names the two receivers, `obs` and `mac`
moved back into the keyword field, paid for by `cable`, which the subtitle now covers.
The video-call intent (`meeting`, `conference`, `call`) and `mic` for the audio feature
added in 0.2.0 stay.

Third-party and Apple trademarks stay out of the keyword field. "Zoom", "Google Meet",
"Teams", "FaceTime" and "Continuity Camera" would all match real search intent, but 2.3.7
warns against packing metadata with trademarked terms, so they appear only in the
description as factual compatibility statements. `obs` and `mac` are the two exceptions:
both are factual compatibility statements about software this app talks to, and both were
in the subtitle before. If App Review ever objects, `mac` is the one to drop first.
Reasoning and A/B candidates: `KEYWORDS-RATIONALE.md`.

## Promotional text (limit 170)

```
Your iPhone as a wired webcam for the Mac: in Zoom, Teams, Meet, FaceTime and any app through the free TetherCam Mac app, or as its own OBS source. No Wi-Fi, no cloud.
```

Editable at any time without shipping a new version, and **this one can be pushed now**,
before 0.3.0 is submitted: the promotional text is not tied to a version. Subtitle,
description and What's New below only take effect with the 0.3.0 submission.

## Description (limit 4000)

```
TetherCam turns your iPhone into a wired USB webcam for the Mac.

Connect the phone with the USB cable you already own. TetherCam captures the camera, encodes the picture in hardware, and hands it to one of two free receivers on the Mac: the TetherCam Mac app, which makes the phone a normal camera for every Mac app, or the TetherCam plugin for OBS Studio, for streaming and recording. Nothing travels over Wi-Fi, nothing passes through a server, and nothing is uploaded anywhere. The cable is the whole path, so the picture stays stable in a crowded room where wireless cameras start to stutter.

ON THE PHONE

Live preview from the moment you open the app, before anything is connected. A camera and lens picker for the wide, ultra wide and telephoto lenses or the front camera, switching the stream immediately.

Automatic rotation that follows the horizon rather than the interface. Turn the phone and the picture stays level, because the orientation is resolved on the capture side. There is a manual angle override when you want to decide yourself.

Hardware HEVC encoding, which keeps the phone cool and the latency low.

A diagnostics panel that shows what is actually happening: listener state, connection, frames per second, bitrate and the measured levelling residual.

ON THE MAC

Two receivers, both free and open source at tethercam.app. Pick one.

The TetherCam Mac app is the simple path and needs macOS 14 or newer. It is a menu bar app with a camera extension: after a one-time approval in System Settings the iPhone appears as the camera "TetherCam" in Zoom, Microsoft Teams, Google Meet, FaceTime, QuickTime Player, Safari and Chrome, in the same camera picker as the built-in one. It carries the picture only. A Mac camera extension has no audio stream, so the sound stays with the Mac's own microphone.

The TetherCam plugin for OBS Studio is the path for streaming and recording. It adds a source called TetherCam directly in OBS and finds the phone through the cable, and it is the only path that also brings the microphone of the phone over that cable.

The phone serves one receiver at a time, so the Mac app and the OBS plugin are not used together; whichever connects second is told that the line is busy. The iPhone app stays open in the foreground while it sends. With no receiver at all the app is still a camera with live preview, lens picker, horizon levelling and diagnostics, it simply has nowhere to send the picture yet.

PRIVACY

No account, no analytics, no advertising, no purchases. The camera picture goes to your own Mac and nowhere else. Nothing is collected.

TetherCam for iPhone is free and open source under the MIT licence at github.com/Kanevry/tethercam.
```

## What's New (limit 4000)

For 0.3.0 (build 6):

```
The TetherCam Mac app turns the iPhone into a camera for every Mac app. Install the free menu bar app from tethercam.app, approve the camera extension once, and the phone shows up as the camera "TetherCam" in Zoom, Teams, Meet, FaceTime, QuickTime Player and browsers. It has been out since 0.2.1; this listing simply never mentioned it. Picture only, macOS 14 or newer.
The app now knows who is receiving. The status line reads "Connected to TetherCam for Mac" or "Connected to OBS" instead of always naming OBS, and it says "Waiting for the Mac" while nothing is connected.
The settings sheet links to both downloads, the Mac app and the OBS plugin, and the microphone note follows the receiver instead of promising audio the Mac app cannot carry.
A second receiver that connects while another one is already streaming is now told so on the phone, instead of being left with a black picture.
"Auto rotation" and the manual angle are remembered between launches, like the horizon levelling already was.
The German system prompt for the microphone is finally in German.
```

Text used for 0.2.0:

```
Audio from the phone. The microphone is sent over the same USB cable and shows up in the OBS audio mixer next to the picture. Needs OBS plugin 0.2.0.
Mute switch in the settings sheet, with a badge in the status capsule while muted.
Double-tap the preview to switch to the next camera. A short note names the lens.
The link now survives a denied microphone and other non-fatal errors instead of reconnecting in a loop.
```

Text used for 0.1.0 (first public release):

```
First public release.

Live preview while the app waits for the Mac, so you can frame the shot before OBS is connected.
Camera and lens switching from the settings sheet.
Automatic rotation with horizon levelling, plus a manual angle override.
Hardware HEVC encoding over the USB cable.
Diagnostics panel with listener state, frame rate, bitrate and levelling residual.
German and English interface.
```

---

## Fields that are not free text

| Field | Value |
|---|---|
| Support URL | `https://tethercam.app/#faq` |
| Marketing URL | `https://tethercam.app` |
| Privacy Policy URL | `https://tethercam.app/privacy` |
| Primary category | Photo & Video |
| Secondary category | Utilities |
| Price | Free (no Paid Applications Agreement needed) |
| Availability | All countries and regions |
| Sign-in required | No, leave unchecked; the app has no account |
| Version release | Manually release this version |
| Copyright | `2026 Bernhard Goetzendorfer` |
| Content rights | Does not contain, show, or access third-party content |
| Export compliance | Uses no non-exempt encryption; `ITSAppUsesNonExemptEncryption` is NO in the build |

## Age rating questionnaire (2025 form)

Answer **None** or **No** to every question. The expected result is **4+**.

| Question group | Answer |
|---|---|
| Violence, cartoon or fantasy / realistic | None |
| Sexual content, nudity, profanity, crude humour | None |
| Alcohol, tobacco, drugs | None |
| Horror or fear themes, mature or suggestive themes | None |
| Simulated gambling, real gambling, contests | None / No |
| Medical or treatment information, health or wellness topics | No |
| Unrestricted web access | No |
| User-generated content or social features, messaging between users | No |
| In-app purchases, advertising | No |
| Capabilities: location sharing, personal information sharing, parental controls | No |
| Made for Kids | No |

## App Privacy answers

"Do you or your third-party partners collect data from this app?" → **No**, resulting in the
label **Data Not Collected**. Rationale, for the record: Apple defines collection as
transmitting data off the device in a way that allows the developer or a partner to access
it, and explicitly exempts data processed only on device. The video leaves the phone only
over the cable to the user's own Mac, never to the developer and never to a third party.
There is no analytics SDK, no account, no crash reporter, no advertising identifier.

## Data types checklist, for the questionnaire dialog

| Data type | Collected |
|---|---|
| Contact info, identifiers, purchases, financial info | No |
| Location | No |
| Contacts, user content, search history, browsing history | No |
| Usage data, diagnostics, crash data, performance data | No |
| Sensitive info, health and fitness | No |
| Other data | No |
