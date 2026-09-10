# Notes for Review

Paste the fenced block into **App Store Connect > Distribution > App Review Information >
Notes**. Same text works for Beta App Review (TestFlight > External Testing > Submit for
Review); shorten only the "Technical notes" list there if you want, but keep the first
paragraph and the demo video link.

Source: `docs/APP-STORE-RELEASE.md` section 4.7, updated 2026-09-05. Changes against the
draft in that section: the demo video is 54 seconds, not 90; the App Preview attached to
the listing is a 30 second cut of the same recording; the in-app privacy policy link
shipped in commit 581a800 and is mentioned so the reviewer does not have to hunt for it.

Updated 2026-09-10 for 0.3.0: the purpose paragraph now names both receivers, the Mac app
first, and the quoted status line is the shipping 0.3.0 wording "Waiting for the Mac".

Updated again 2026-09-10 for the 0.3.1 / next submission (issue #31): the purpose paragraph
leads with the two-apps picture — TetherCam for Mac plus TetherCam for iPhone, one cable —
states that the camera appears in every Mac app that lists system cameras, names Zoom and
Microsoft Teams as verified on 2026-09-10, and demotes OBS to one tool among many. The
three limits a reviewer will otherwise discover on their own are stated up front: the Mac
app carries video only, this app stays in the foreground while it sends, and the phone
serves one receiver at a time.

The 4.2.3 App Independence defence comes first on purpose. It is the highest-probability
rejection reason (see section 1, risk 1), and a reviewer with a stopwatch reads the first
paragraph.

```
What the app does without any additional software

TetherCam is a camera app. On launch it opens a live preview from the rear camera and works fully standalone: you can switch camera and lens, enable or disable automatic rotation and horizon levelling, set a manual angle, and open a diagnostics panel. Please try these first. The status line "Waiting for the Mac" is informational; nothing is blocked behind it. No second iOS app is required, and nothing is downloaded at runtime.

Why you cannot exercise the full flow, and what it is

The purpose of the app is to replace a webcam: it delivers that camera picture to a Mac over the USB cable. TetherCam is two apps, and this is the iPhone half. The other half is the TetherCam Mac app, a free menu bar app with a camera extension that makes the iPhone appear as the camera "TetherCam" on the Mac, in the same camera picker as the built-in one, in every Mac app that lists system cameras: Zoom and Microsoft Teams (both verified on 10 September 2026), Google Meet, FaceTime, QuickTime Player, Safari and Chrome. A second, optional receiver is the TetherCam plugin for OBS Studio, for streaming and recording; OBS is one tool among many, not the point of the app. Both receivers are free and open source and are downloaded from https://tethercam.app. Three limits, stated so they are not a surprise: the Mac app carries the picture only, because a Mac camera extension has no audio stream (only the OBS plugin also carries the phone microphone); this iPhone app stays open in the foreground while it sends; and the phone serves one receiver at a time. There is no account and no pairing code. The app opens a TCP listener on port 7878 on the device. A Mac connected by cable reaches that port through the usbmux tunnel provided by Apple's usbmuxd, the same mechanism Xcode and Finder use for a wired device. There is no Wi-Fi, no Bonjour, no discovery, no server anywhere. Both receivers are Mac desktop software, not iOS apps, and reviewing them is not required in order to review this app. A second receiver that connects while one is already streaming is turned away with a "busy" message shown on the phone.

Demo video

A 54 second screen recording of the complete flow, an iPhone plugged into a Mac and the picture appearing as a source in OBS: https://tethercam.app/demo.mp4

Timestamps in that recording: 0:00 the app standalone with live preview, settings and diagnostics; 0:13 the USB cable going into the Mac; 0:22 the TetherCam source being added in OBS on the Mac; 0:30 onwards the live picture arriving in OBS at 1080p30 with horizon levelling. The App Preview attached to this listing is a 30 second cut of the same recording (0:05 to 0:34).

Technical notes

- No background modes are requested. Capture runs in the foreground only.
- NSCameraUsageDescription covers the camera. NSLocalNetworkUsageDescription is present because the listener is bound on the device rather than restricted to loopback; iOS classifies that as local network activity even though the only client is the attached Mac.
- No encryption beyond what the OS provides. ITSAppUsesNonExemptEncryption is NO.
- No accounts, no sign-in, no analytics, no advertising, no purchases, no third-party SDKs. App Privacy is answered as Data Not Collected because nothing leaves the device except to the user's own Mac over the cable.
- The privacy policy is linked inside the app: gear icon, Settings sheet, bottom section, "Privacy policy", opening https://tethercam.app/privacy
- iPhone only, landscape only, iOS 17 and later.
- The iOS app is open source under the MIT licence: https://github.com/Kanevry/tethercam

Contact: office@gotzendorfer.at
```

## If the app is rejected on 4.2.3 or 2.1

Do not resubmit an unchanged binary. Reply in the Resolution Center with the standalone
feature list plus a timestamp into the demo video, per `docs/APP-STORE-RELEASE.md`
section 3, closing paragraph. Most 4.2.3 rejections of companion-hardware apps are resolved
in writing rather than by code changes.
