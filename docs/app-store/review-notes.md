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

The 4.2.3 App Independence defence comes first on purpose. It is the highest-probability
rejection reason (see section 1, risk 1), and a reviewer with a stopwatch reads the first
paragraph.

```
What the app does without any additional software

TetherCam is a camera app. On launch it opens a live preview from the rear camera and works fully standalone: you can switch camera and lens, enable or disable automatic rotation and horizon levelling, set a manual angle, and open a diagnostics panel. Please try these first. The status line "Waiting for the Mac" is informational; nothing is blocked behind it. No second iOS app is required, and nothing is downloaded at runtime.

Why you cannot exercise the full flow, and what it is

The purpose of the app is to deliver that camera picture to a Mac over the USB cable, where one of two free receivers picks it up. The default one is the TetherCam Mac app, a menu bar app with a camera extension that makes the iPhone appear as the camera "TetherCam" in Zoom, Teams, Google Meet, FaceTime, QuickTime Player and browsers; the second is the TetherCam plugin for OBS Studio, for streaming and recording. Both are free and open source and are downloaded from https://tethercam.app. The app opens a TCP listener on port 7878 on the device. A Mac connected by cable reaches that port through the usbmux tunnel provided by Apple's usbmuxd, the same mechanism Xcode and Finder use for a wired device. There is no Wi-Fi, no Bonjour, no discovery, no server anywhere. Both receivers are Mac desktop software, not iOS apps, and reviewing them is not required in order to review this app. The phone serves one receiver at a time; a second one is turned away with a "busy" message shown on the phone.

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
