# App Store metadata: English (U.S.), primary localization

Version 0.1.0, build 2. Bundle id `at.gotzendorfer.tethercam`. Free. iPhone only, landscape
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
USB webcam for Mac and OBS
```

## Keywords (limit 100)

```
cable,tether,wired,camcorder,streaming,capture,meeting,conference,call,video,live,studio,cam,mic
```

Comma separated, no spaces after commas, 96 of 100 characters. Words from the name and the
subtitle are not repeated; Apple indexes those already, which is why `usb`, `webcam`, `mac`
and `obs` no longer appear here: the subtitle "USB webcam for Mac and OBS" carries all four.
That freed the field for the intents the old list missed, above all the video-call side
(`meeting`, `conference`, `call`) and `mic` for the audio feature added in 0.2.0.

Third-party and Apple trademarks stay out of the keyword field. "Zoom", "Google Meet",
"Teams", "FaceTime" and "Continuity Camera" would all match real search intent, but 2.3.7
warns against packing metadata with trademarked terms, so they appear only in the
description as factual compatibility statements. "OBS" is the one exception and lives in
the subtitle, as it did before. Reasoning and A/B candidates: `KEYWORDS-RATIONALE.md`.

## Promotional text (limit 170)

```
Turn the iPhone into a USB webcam for the Mac: into OBS Studio, and into video calls through the OBS virtual camera. No Wi-Fi, no cloud, no lag. Free and open source.
```

Editable at any time without shipping a new version.

## Description (limit 4000)

```
TetherCam turns your iPhone into a wired USB webcam for the Mac.

Connect the phone with the USB cable you already own. TetherCam captures the camera, encodes the picture in hardware, and hands it to the free TetherCam plugin for OBS Studio on the Mac; from OBS the same picture goes on into a video call, a screen recording or a live stream through the OBS virtual camera. Nothing travels over Wi-Fi, nothing passes through a server, and nothing is uploaded anywhere. The cable is the whole path, so the picture stays stable in a crowded room where wireless cameras start to stutter.

ON THE PHONE

Live preview from the moment you open the app, before anything is connected. A camera and lens picker for the wide, ultra wide and telephoto lenses or the front camera, switching the stream immediately.

Automatic rotation that follows the horizon rather than the interface. Turn the phone and the picture stays level, because the orientation is resolved on the capture side. There is a manual angle override when you want to decide yourself.

Hardware HEVC encoding, which keeps the phone cool and the latency low.

A diagnostics panel that shows what is actually happening: listener state, connection, frames per second, bitrate and the measured levelling residual.

ON THE MAC

The TetherCam plugin for OBS Studio, a free and open source download from tethercam.app. It adds a source called TetherCam and finds the phone through the cable. Without the plugin the app still works as a camera with preview and settings, it simply has nowhere to send the picture.

PRIVACY

No account, no analytics, no advertising, no purchases. The camera picture goes to your own Mac and nowhere else. Nothing is collected.

TetherCam for iPhone is free and open source under the MIT licence at github.com/Kanevry/tethercam.
```

## What's New (limit 4000)

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
