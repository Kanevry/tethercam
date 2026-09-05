# TetherCam on the App Store: review risks, TestFlight, and submission

Scope: the iOS app `at.gotzendorfer.tethercam` (team G3QZ66475M, Bernhard Goetzendorfer,
Austria). The macOS OBS plugin is GPL-2.0-or-later and is not distributed through the
App Store; it stays on GitHub releases and https://tethercam.app. This document
complements `docs/RELEASING.md`, which covers certificates, secrets and the tag runbook.
Everything here is about App Store Connect, App Review and store metadata.

Researched against Apple sources in September 2026. All URLs in section 7.

---

## 1. Verdict

**TestFlight: yes, with high confidence.** Beta App Review is lighter than App Review,
and the app already does something visible without the Mac: since commit 26df7a8 it shows
a live camera preview plus the status line while it waits for OBS. That single feature is
what makes the app reviewable at all.

**App Store: yes, but expect one rejection round on guideline 4.2.3(i) unless the review
notes and the screenshots are written specifically to pre-empt it.**

### Top risks, in order

**Risk 1 (high): 4.2.3 App Independence.** Verbatim: *"Your app should work on its own
without requiring installation of another app to function."* TetherCam's headline
function requires an OBS plugin on a Mac that the reviewer will not install. The
mitigation is already in the binary: the app launches into a live preview, exposes the
camera and lens picker, auto rotation, horizon leveling and a diagnostics panel, all
without any Mac. Argue this explicitly in the review notes and prove it in screenshot 1.
Do not describe the app as a "client" or an "accessory" for the plugin. Note the wording
of the guideline: another *app*. A companion piece of desktop software on a different
platform is not the case 4.2.3 targets (that rule exists for iOS apps that are useless
without a second iOS app), but a reviewer with a stopwatch reads the marketing line
first, so the burden of proof is yours.

**Risk 2 (high): 2.1 App Completeness.** The reviewer cannot reproduce the core flow.
Guideline 2.1(a) demands final builds and, where the flow cannot be exercised, prior
agreement on a demo path. There is no demo account here, so the substitute is a review
note that is specific plus a demo video. 2.3.1(a) is the sharper edge: *"All new features,
functionality, and product changes must be described with specificity in the Notes for
Review section of App Store Connect (generic descriptions will be rejected)."*
The notes must state, in order: what the app does standalone, why the USB path cannot be
exercised by the reviewer, where the receiving software lives, that it is free and open
source, and a link to a 60 to 90 second screen recording that shows an iPhone plugged
into a Mac with the picture arriving in OBS.

**Risk 3 (medium): 5.1.1(i) privacy policy inside the app.** Verbatim: *"All apps must
include a link to their privacy policy in the App Store Connect metadata field **and
within the app in an easily accessible manner**."* Today `ios-app/Sources/UI/ContentView.swift`
has exactly one outbound `Link`, to `https://tethercam.app`, labelled "install plugin".
There is no privacy policy link in the settings sheet. **This is a code change that must
happen before the first App Store submission.** Add a second `Link` to
`https://tethercam.app/privacy` in the last settings section. TestFlight does not enforce
this, the App Store does.

**Risk 4 (medium): export compliance is unanswered.** `ios-app/project.yml` sets many
`INFOPLIST_KEY_*` values but not `ITSAppUsesNonExemptEncryption`. Without the key every
single build lands in "Missing Compliance" in App Store Connect and cannot be released
to external testers until answered by hand. The app uses no encryption at all (the wire
protocol is plain framed HEVC over a loopback-class TCP socket, see `protocol/PROTOCOL.md`),
so the answer is NO. Add to the `TetherCam` target in `project.yml`:

```yaml
        INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
```

**Risk 5 (medium): 5.1.1(ii) purpose strings.** *"Ensure your purpose strings clearly and
completely describe your use of the data."* The current camera string, "The camera picture
is sent to the Mac over the USB cable", is good: it names the recipient and the transport.
Weakness: it is only true once a Mac is attached, and the app now previews before that.
Suggested replacement in section 4. `NSLocalNetworkUsageDescription` is present and needed:
`UsbServer.swift` creates `NWListener(using: params, on: 7878)` with no
`requiredInterfaceType(.loopback)`, so the listener is bound on all interfaces and iOS
treats it as local network activity. Leave the key in place. Do not claim in metadata that
the app "has no network access"; say that it never sends data to a server, which is true.

**Risk 6 (low to medium): 5.2.5 and the Apple trademark rules in metadata.** Apple's
marketing guidelines are explicit: Apple product names cannot appear in the app name, and
never as the leading word. `TetherCam` is clean. In the description the referential forms
are the allowed ones: "TetherCam for iPhone", "works with Mac", never "iPhone camera app"
as a construction. About "Continuity Camera": it is an Apple feature name. Using it in the
**app name, subtitle or keyword field is not worth the risk** (2.3.7 forbids packing
metadata with trademarked terms). One factual, non-disparaging sentence in the description
that names it as the thing users already know is defensible, but the safer draft in
section 4 avoids it entirely and describes the mechanism instead. That is the recommendation.

**Risk 7 (low): 4.2 Minimum Functionality.** A camera preview plus a socket is thin on
paper. Countered by the horizon leveling, the rotation coordinator work, the lens picker
and the diagnostics. Make the screenshots show these, not just a viewfinder. 2.3.3 also
forbids screenshots that are only title art or a splash screen.

**Risk 8 (low): 2.3.10, other platforms in metadata.** *"don't include names, icons, or
imagery of other mobile platforms."* OBS Studio and macOS are neither mobile platforms nor
alternative marketplaces, so mentioning them is fine. Do not mention Android, Windows or
Linux support of the OBS plugin anywhere in App Store metadata, even though the wider
project may run there.

**Risk 9 (low): 2.5.4 background.** The app captures only in the foreground and requests
no background modes. Say so in the review notes in one sentence; it removes a question
before it is asked.

**Non-risks, confirmed.**
- **Open source and licensing.** 4.7 governs mini apps, plug-ins, chatbots and emulators
  shipping executable content inside your binary. It does not apply. The iOS app is MIT
  and ships no downloaded code, so 2.5.2 is satisfied. GPL is the real trap and you have
  already avoided it: GPL-2.0 is incompatible with the App Store terms, and none of the
  GPL code lives in `ios-app/`; the OBS plugin is distributed outside the store. Keep that
  boundary absolute. Never link GPL code into the iOS target.
- **Name collision.** A search of the iTunes Search API (US and AT storefronts, September
  2026) returns no app named TetherCam or Tether Cam. Nearest neighbours are Camo Camera
  (Reincubate), DroidCam, iVCam and Cascable Studio: Tether & More. None is a
  confusable-name problem. A store search is not a trademark search: if the name matters
  commercially, do a separate EUIPO and USPTO check before the App Store release, because
  2.3.7 requires a unique name and Apple removes names on a rights holder complaint.
- **App Privacy label.** "Data Not Collected" is correct. Apple defines collection as
  *"transmitting data off the device in a way that allows you and/or your third-party
  partners to access it"*, and adds *"Data that is processed only on device is not
  'collected'."* Video leaves the phone only to the user's own Mac over the cable, never
  to you or a partner. There is no analytics SDK, no account, no crash reporter.
- **Age rating.** Everything answers to the lowest band; the app has no user content, no
  web view, no contact between users. Expect 4+.

---

## 2. TestFlight path, step by step

Automated already, do not redo by hand: `.github/workflows/testflight-ios.yml` generates
the project with xcodegen, archives with `-allowProvisioningUpdates`, and exports with
`packaging/ExportOptions.plist` (`method: app-store-connect`, `destination: upload`), so a
single `xcodebuild -exportArchive` uploads the build. Triggered by a `v*` tag or by
`workflow_dispatch`. It skips cleanly when `ASC_KEY_P8` is absent.

### 2.1 Owner steps, before the first upload

**O1. Confirm the Apple Developer Program membership is active.**
developer.apple.com > Account > Membership details. Expiry, team ID G3QZ66475M, and the
Account Holder is you. An expired membership fails the upload with a signing error that
looks like a provisioning bug.

**O2. Declare EU trader status.** Since 17 February 2025 apps without a verified trader
status are removed from the EU App Store, and updates are blocked. As an Austrian
developer distributing in the EU this is unavoidable and it takes verification time, so do
it first. App Store Connect > Business (or Users and Access > Compliance, depending on
account type) > Trader Status. You must supply address, phone and email; those become
public on the product page. Declare truthfully whether you act as a trader.

**O3. Accept the agreements.** App Store Connect > Business > Agreements. The Apple
Developer Program License Agreement must be current. The Paid Applications Agreement is
**not** required for a free app; skip it unless you later charge.

**O4. Create the app record. This cannot be automated.** Apple's own API documentation
says *"Don't use this API to create new apps; instead, create new apps on the App Store
Connect website."* Path: App Store Connect > Apps > `+` > New App. Platform iOS, Name
`TetherCam`, Primary Language English (U.S.), Bundle ID `at.gotzendorfer.tethercam`
(pick the registered identifier, do not use a wildcard), SKU `tethercam-ios`, User Access
Full. The bundle id can never be changed afterwards.

**O5. Create the App Store Connect API key for uploads.** App Store Connect > Users and
Access > Integrations > App Store Connect API > Team Keys > `+`. **Role: App Manager**
(Admin also works). Note the difference from `docs/RELEASING.md` step 1c: the notarization
key there is role Developer, which is enough for notarytool but not for TestFlight
distribution and metadata. Use a separate key. The `.p8` downloads exactly once.
Only the Account Holder can request API access and generate team keys.
Then set the GitHub secrets: `ASC_KEY_P8` (base64 of the `.p8`), `ASC_KEY_ID`,
`ASC_ISSUER_ID`.

**O6. Fill the App Privacy questionnaire.** App Store Connect > your app > App Privacy >
Get Started. Answer "No" to "Do you or your third-party partners collect data from this
app?" Publish. This is required before any external TestFlight distribution.

### 2.2 Code changes before the first upload

**C1.** Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` to `ios-app/project.yml`
(both targets is harmless; the app target is what matters).
**C2.** Optional for TestFlight, mandatory for the App Store: the in-app privacy policy
link (risk 3). Doing it now avoids a second review cycle later.
**C3.** Publish `https://tethercam.app/privacy` and make sure it returns 200 before you
enter it anywhere. 2.1(a) rejects placeholder pages and dead URLs.

### 2.3 Upload and internal testing

1. Push a tag `v0.1.0`, or run the workflow with `workflow_dispatch`.
2. Wait for processing in App Store Connect > TestFlight > iOS builds, typically 5 to 30
   minutes. If "Missing Compliance" appears, C1 was not applied; answer it by hand once.
3. Internal testers: up to 100 App Store Connect users on your team, no review, available
   within minutes. Test here first.

### 2.4 Public link

An internal group must exist before external groups can be created.

1. App Store Connect > your app > TestFlight > Test Information. Fill in beta app
   description, feedback email, and what to test. Required before external distribution.
2. Sidebar, `+` next to **External Testing** > name the group `Public Beta` > Create.
3. In the group: **Add Builds** > pick the build > fill "What to Test" > **Submit Review**.
   Beta App Review is required for the first build of a version; later builds of the same
   version usually skip it. Up to 6 builds per 24 hours may be submitted for review.
   Budget one to two working days for the first pass.
4. When the status turns **Testing**: group > **Testers** tab > **Create Public Link** >
   **Open to Anyone** (or Filter by Criteria to require iOS 17+, which matches the
   deployment target) > optional tester limit 1 to 10,000 > Confirm > copy the URL.
5. Publish the URL on https://tethercam.app.

Operating facts: 10,000 external testers per app; every build expires 90 days after
upload and testers then see "This beta has expired", so ship a fresh build at least
quarterly; public link testers are anonymous, you see installs, sessions and crashes but
no names.

The review notes for Beta App Review can be shorter than the App Store ones, but keep the
same first paragraph and the same demo video link.

---

## 3. App Store path, step by step

Prerequisites: everything in section 2, plus C2 (in-app privacy link) actually shipped.

1. **App Store Connect > your app > Distribution > iOS App > 1.0 Prepare for Submission.**
2. **Metadata.** Paste from section 4. Limits: name 30, subtitle 30, keywords 100,
   promotional text 170, description 4000, what's new 4000, per localization. Provide
   en-US as primary. German (Austria) is optional; the app already ships `de.lproj`, so a
   de-DE localization is cheap and worth doing.
3. **URLs.** Support `https://tethercam.app/#faq`, Marketing `https://tethercam.app`,
   Privacy Policy `https://tethercam.app/privacy`. Guideline 1.5 requires a genuinely
   usable support contact behind the support URL, so the FAQ anchor must carry a mail
   address or an issue link.
4. **Categories.** Primary **Photo & Video**, Secondary **Utilities**. 2.3.6 asks for the
   most appropriate category; the app produces a video signal, so Photo & Video is right,
   and Utilities carries the tool character.
5. **Screenshots.** `ios-app/project.yml` sets `TARGETED_DEVICE_FAMILY: "1"`, iPhone only,
   so **no iPad screenshots are required or accepted**. Apple's specification requires at
   least one iPhone set: either the **6.9" display (1260 x 2736 portrait, or 2736 x 1260
   landscape)** or the **6.5" display (1284 x 2778 / 2778 x 1284)**. Other sizes are
   auto-scaled. The app is landscape only (`UISupportedInterfaceOrientations_iPhone` is
   the two landscape values), so deliver **landscape** shots at 2736 x 1260. One to ten
   are allowed; ship four:
   - 1: live preview with the status line, captioned "Works before the Mac is even
     plugged in". This is the 4.2.3 defence, so it must be first.
   - 2: settings sheet with camera and lens picker.
   - 3: horizon leveling and auto rotation.
   - 4: diagnostics panel with fps, kbps and port, or the picture inside OBS on a Mac.
     Note that a Mac screenshot inside an iPhone screenshot set is unusual; if you use it,
     make it clearly a photo of the workflow, not a fake device frame.
   No alpha channel, `.png` or `.jpg`.
6. **App icon.** 1024 x 1024 already exists at
   `ios-app/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` and is compiled
   into the binary; App Store Connect takes it from the build.
7. **Age rating.** App Store Connect > your app > Age Rating > Edit. The questionnaire was
   overhauled in 2025: the bands are now 4+, 9+, 13+, 16+, 18+, and Apple required every
   app to answer the added questions (in-app controls, capabilities, medical or wellness,
   violent themes) by 31 January 2026, blocking submissions otherwise. Answer None or No
   throughout. Expect 4+.
8. **Pricing and availability.** Price tier Free. Availability: all countries and regions,
   or narrow it if you prefer to support fewer languages. Free means no Paid Applications
   Agreement and no banking or tax forms.
9. **Sign-in information.** Leave "Sign-in required" unchecked. There is no account.
10. **Notes for Review.** Paste section 4.7. Include the demo video URL and a contact
    email. Attach nothing else; a URL in the notes is enough.
11. **Version release.** Choose "Manually release this version" for 1.0 so the store page
    goes live when your website and the plugin download are ready, not at Apple's whim.
12. **Build.** Select the processed build, confirm export compliance shows as answered.
13. **Add for Review > Submit.** Then watch App Store Connect > App Review for status.

If rejected on 4.2.3 or 2.1: do not resubmit unchanged. Reply in Resolution Center with a
timestamped pointer into the demo video and the sentence that the app runs standalone as a
camera with preview, leveling and diagnostics. Most 4.2.3 rejections of companion-hardware
apps are resolved in the Resolution Center rather than by code changes.

---

## 4. Metadata drafts, ready to paste

### 4.1 App name (30 max)

```
TetherCam
```

Alternative if a collision ever appears: `TetherCam Studio` (16). Do not use "iPhone" or
"Mac" in the name field; Apple's marketing guidelines forbid Apple product names in app
names.

### 4.2 Subtitle (30 max)

```
Wired camera for OBS
```
20 characters. Fallback with the compatibility construction, which the marketing
guidelines permit as a referential use: `USB camera for OBS on Mac` (25). The shorter one
is recommended because it keeps trademarked terms out of the subtitle entirely (2.3.7).

### 4.3 Keywords (100 max, comma separated, no spaces after commas)

```
usb,cable,tether,webcam,stream,broadcast,capture,hevc,camera,video,studio,live,wired,cam
```
88 characters. Do not repeat words from the name or subtitle; Apple indexes those already.
"obs" is deliberately absent: OBS Studio is a third-party trademark and 2.3.7 warns
against packing metadata with trademarked terms. It appears in the subtitle and
description as a factual compatibility statement, which is the safer placement.

### 4.4 Promotional text (170 max, editable without a new version)

```
Plug the iPhone into the Mac and the camera picture lands in OBS. No Wi-Fi, no cloud, no network lag. Free, open source, and previewing the moment you launch it.
```

### 4.5 Description (4000 max, the draft below is about 1500)

```
TetherCam turns your iPhone into a wired camera for live production on the Mac.

Connect the phone with the USB cable you already own. TetherCam captures the camera, encodes the picture in hardware, and hands it to the free TetherCam plugin for OBS Studio on the Mac. Nothing travels over Wi-Fi, nothing passes through a server, and nothing is uploaded anywhere. The cable is the whole path, so the picture stays stable in a crowded room where wireless cameras start to stutter.

On the phone:

Live preview from the moment you open the app, before anything is connected. A camera and lens picker for the wide, ultra wide and telephoto lenses or the front camera, switching the stream immediately.

Automatic rotation that follows the horizon rather than the interface. Turn the phone and the picture stays level, because the orientation is resolved on the capture side. There is a manual angle override when you want to decide yourself.

Hardware HEVC encoding, which keeps the phone cool and the latency low.

A diagnostics panel that shows what is actually happening: listener state, connection, frames per second, bitrate and the measured levelling residual.

On the Mac:

The TetherCam plugin for OBS Studio, a free and open source download from tethercam.app. It adds a source called TetherCam and finds the phone through the cable. Without the plugin the app still works as a camera with preview and settings, it simply has nowhere to send the picture.

Privacy: no account, no analytics, no advertising, no purchases. The camera picture goes to your own Mac and nowhere else. Nothing is collected.

TetherCam for iPhone is free and open source under the MIT licence at github.com/Kanevry/tethercam.
```

### 4.6 What's New, version 0.1.0

```
First public release.

Live preview while the app waits for the Mac, so you can frame the shot before OBS is connected.
Camera and lens switching from the settings sheet.
Automatic rotation with horizon levelling, plus a manual angle override.
Hardware HEVC encoding over the USB cable.
Diagnostics panel with listener state, frame rate, bitrate and levelling residual.
German and English interface.
```

### 4.7 Notes for Review (paste into App Review Information)

```
What the app does without any additional software

TetherCam is a camera app. On launch it opens a live preview from the rear camera and works fully standalone: you can switch camera and lens, enable or disable automatic rotation and horizon levelling, set a manual angle, and open a diagnostics panel. Please try these first. The status line "Waiting for OBS on the Mac" is informational; nothing is blocked behind it.

Why you cannot exercise the full flow, and what it is

The purpose of the app is to deliver that camera picture to OBS Studio on a Mac over the USB cable. The app opens a TCP listener on port 7878 on the device. A Mac connected by cable reaches that port through the usbmux tunnel provided by Apple's usbmuxd, the same mechanism Xcode and Finder use for a wired device. There is no Wi-Fi, no Bonjour, no discovery, no server anywhere. The receiving side is a free, open source plugin for OBS Studio that the user installs on the Mac from https://tethercam.app. It is not an iOS app, and reviewing it is not required in order to review this app.

Demo video

A 90 second screen recording of the complete flow, an iPhone plugged into a Mac and the picture appearing as a source in OBS: https://tethercam.app/demo.mp4

Technical notes

- No background modes are requested. Capture runs in the foreground only.
- NSCameraUsageDescription covers the camera. NSLocalNetworkUsageDescription is present because the listener is bound on the device rather than restricted to loopback; iOS classifies that as local network activity even though the only client is the attached Mac.
- No encryption beyond what the OS provides. ITSAppUsesNonExemptEncryption is NO.
- No accounts, no sign-in, no analytics, no advertising, no purchases, no third-party SDKs. App Privacy is answered as Data Not Collected because nothing leaves the device except to the user's own Mac over the cable.
- The iOS app is open source under the MIT licence: https://github.com/Kanevry/tethercam

Contact: office@gotzendorfer.at
```

### 4.8 Purpose strings, suggested replacements in `ios-app/project.yml`

```yaml
        INFOPLIST_KEY_NSCameraUsageDescription: "TetherCam shows the camera picture on the phone and sends it to your Mac over the USB cable. It is never uploaded anywhere."
        INFOPLIST_KEY_NSLocalNetworkUsageDescription: "TetherCam opens a listener on port 7878 so the Mac connected by cable can receive the picture. No data is sent over Wi-Fi."
```
Mirror both in `ios-app/Sources/Resources/en.lproj/InfoPlist.strings` and `de.lproj`.

---

## 5. Privacy policy draft for https://tethercam.app/privacy

```
Privacy Policy for TetherCam

Last updated: <DATE>
Responsible: Bernhard Goetzendorfer, <POSTAL ADDRESS>, Austria. Contact: office@gotzendorfer.at

What data TetherCam collects

None. TetherCam does not collect, transmit, store or share any personal data. There is no
user account, no registration, no analytics, no crash reporting, no advertising and no
third-party SDK of any kind in the app.

How the camera is used

TetherCam accesses the camera in order to show a live preview on the phone and to encode
the picture for transfer to a Mac connected by USB cable. The picture is encoded on the
device and sent over the cable to the TetherCam plugin for OBS Studio running on that Mac.
It is sent nowhere else. TetherCam operates no server and has no cloud component. The
video is not recorded to the photo library and is not written to disk by the app.

Network

The app opens a TCP listener on port 7878 on the device so that the connected Mac can
reach it through the USB connection. iOS classifies a listener of this kind as local
network activity, which is why the app asks for local network permission. The app makes no
outbound internet connections other than opening the links you tap, such as tethercam.app.

Motion data

TetherCam reads device orientation from CoreMotion in order to keep the picture level with
the horizon. This data is used in the moment, on the device, and is never stored or
transmitted.

Data retention and deletion

Because no data is collected, there is nothing retained and nothing to delete. Deleting
the app removes its local settings from the device. If you wish to withdraw camera or
motion access, use Settings, Privacy and Security on the phone.

Third parties

No user data is shared with any third party, because none is collected. The app contains
no analytics or advertising networks.

Children

TetherCam contains no user-generated content, no messaging and no external content. It is
suitable for all ages.

Changes

Changes to this policy will be published on this page with a new date at the top.
```

---

## 6. Owner checklist

Steps only the owner can do, in order. Nothing here can be moved into CI.

1. **Membership.** developer.apple.com > Account > Membership details. Confirm active,
   team G3QZ66475M, and note the renewal date.
2. **EU trader status.** App Store Connect > Business > Trader Status. Declare, submit
   address, phone and email, wait for verification. Do this first; it gates EU
   distribution and takes days, not minutes.
3. **Agreements.** App Store Connect > Business > Agreements. Accept the current Apple
   Developer Program License Agreement. Skip Paid Applications; the app is free.
4. **Bundle identifier.** developer.apple.com > Certificates, Identifiers & Profiles >
   Identifiers. Confirm `at.gotzendorfer.tethercam` exists as an explicit App ID.
5. **App record.** App Store Connect > Apps > `+` > New App. iOS, `TetherCam`, English
   (U.S.), bundle id `at.gotzendorfer.tethercam`, SKU `tethercam-ios`. Cannot be done via
   the API.
6. **API key for distribution.** App Store Connect > Users and Access > Integrations >
   App Store Connect API > Team Keys > `+` > role **App Manager** > download the `.p8`
   once. This is a different key from the notarization key in `docs/RELEASING.md` 1c.
7. **GitHub secrets.** github.com/Kanevry/tethercam > Settings > Secrets and variables >
   Actions. Add `ASC_KEY_P8` (`base64 -i AuthKey_XXXX.p8 | pbcopy`), `ASC_KEY_ID`,
   `ASC_ISSUER_ID`. Delete the `.p8` from disk afterwards.
8. **Two code changes (DONE 2026-09-05, commit 581a800).** Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` to
   `ios-app/project.yml`, and add a privacy policy `Link` to the settings sheet in
   `ios-app/Sources/UI/ContentView.swift`. Commit both before the first upload.
9. **Publish the website pages (DONE 2026-09-05: /privacy and /#faq live).** `https://tethercam.app/privacy` with section 5, and an
   `#faq` anchor on the landing page that contains a working contact address. Verify both
   return 200 in a private browser window. Placeholder pages violate 2.1(a).
10. **App Privacy.** App Store Connect > your app > App Privacy > Get Started > "No" to
    data collection > Publish.
11. **Age rating.** App Store Connect > your app > Age Rating > Edit. Answer the 2025
    questionnaire, all None or No. Confirm the result reads 4+.
12. **Ship the build.** Push tag `v0.1.0`, or run the `testflight-ios` workflow via
    workflow_dispatch. Wait for processing.
13. **TestFlight test information.** App Store Connect > TestFlight > Test Information.
    Beta description, feedback email, what to test.
14. **External group and Beta App Review.** TestFlight > `+` next to External Testing >
    `Public Beta` > Add Builds > What to Test > Submit Review. Wait for status Testing.
15. **Public link.** Group > Testers > Create Public Link > Open to Anyone > copy > publish
    on tethercam.app. Remember the 90-day build expiry.
16. **Record the demo video (DONE 2026-09-05: https://tethercam.app/demo.mp4, 54 s, owner-approved).** 60 to 90 seconds, iPhone plugged into a Mac, plugin picking
    up the source in OBS, ending on the diagnostics panel. Host it somewhere stable and put
    the URL into `https://tethercam.app/demo.mp4` in section 4.7.
17. **Screenshots.** Four landscape 2736 x 1260 shots per section 3.5. Screenshot 1 must
    show the standalone preview.
18. **App Store submission.** Distribution > 1.0 Prepare for Submission. Paste section 4,
    select Photo & Video plus Utilities, price Free, availability, "Manually release this
    version", select the build, paste the review notes, Add for Review > Submit.
19. **If rejected on 4.2.3 or 2.1.** Reply in Resolution Center with a timestamp into the
    demo video and the standalone-features paragraph. Do not resubmit an unchanged binary.

---

## 7. Sources

App Review Guidelines (2.1, 2.3.x, 2.5.x, 4.2.3, 4.7, 5.1.1, 5.2.5, 1.5):
https://developer.apple.com/app-store/review/guidelines/

Marketing Resources and Identity Guidelines, use of Apple trademarks in app names and
descriptions: https://developer.apple.com/app-store/marketing/guidelines/

Apple copyright and trademark guidelines for third parties:
https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html

App Privacy Details, definition of "collect" and the on-device exemption:
https://developer.apple.com/app-store/app-privacy-details/

Screenshot specifications, required iPhone and iPad sizes:
https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/

App information reference, name and subtitle limits:
https://developer.apple.com/help/app-store-connect/reference/app-information/

TestFlight overview, tester limits, 90-day expiry, review requirement:
https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview

Invite external testers, public link creation, required roles:
https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers

Provide test information for TestFlight:
https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/

Add a new app (app record creation on the website):
https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app

Role permissions in App Store Connect:
https://developer.apple.com/support/roles/

Overview of export compliance and ITSAppUsesNonExemptEncryption:
https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance

Updated age ratings in App Store Connect (2025 overhaul, 31 January 2026 deadline):
https://developer.apple.com/news/?id=ks775ehf

DSA trader status required for apps in the EU:
https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
https://developer.apple.com/news/upcoming-requirements/?id=02172025a

App Store Connect API, "Don't use this API to create new apps":
https://developer.apple.com/documentation/appstoreconnectapi

App Store category definitions:
https://developer.apple.com/app-store/categories/

Name collision check performed against the iTunes Search API, US and AT storefronts,
September 2026: https://itunes.apple.com/search?term=tethercam&entity=software

---

## Update 2026-09-05

Nothing above is retracted. This section records what was produced since, and the three
places where the drafts above are now superseded by files under `docs/app-store/`.

**Paste-ready metadata now lives in `docs/app-store/`.** Section 4 stays as the reasoning
record; the files are what gets pasted.

- `docs/app-store/en-US.md`: name, subtitle, keywords, promotional text, description,
  what's new, URLs, categories, copyright `2026 Bernhard Goetzendorfer`, the age-rating
  answer table and the App Privacy answer table.
- `docs/app-store/de-DE.md`: the German localization. Neutral phrasing throughout, neither
  "du" nor "Sie", which reads correctly in Austria and in Germany. Register it as German
  (de-DE); there is no de-AT slot.
- `docs/app-store/review-notes.md`: the Notes for Review, 4.2.3 defence first.
- `docs/app-store/checklist.md`: the App Store Connect click path, 34 steps, each marked
  OWNER or AUTOMATED, cross-referenced back into this document.
- `docs/app-store/validate.sh`: checks every character limit in both localizations and the
  dimensions and duration of the media. `bash docs/app-store/validate.sh` exits 0 today.

**Correction to section 4.7: the demo video is 54 seconds, not 90.** It is live at
https://tethercam.app/demo.mp4 and owner-approved. The review notes now quote 54 seconds
and add per-scene timestamps (0:00 standalone, 0:13 cable, 0:22 source added in OBS, 0:30
picture arriving), which is what 2.3.1(a) means by specificity.

**Correction to section 3.5 on screenshot size.** The existing device shots in
`docs/images/` are 2796 x 1290, not 2736 x 1260. Both are accepted for the iPhone 6.9"
landscape slot, so no re-capture is needed. Four shots, no alpha, staged for upload at
`~/Desktop/TetherCam-AppStore/screenshots-6.9/`:

| File | Source in `docs/images/` | Purpose |
|---|---|---|
| `01-live-preview.png` | `app-live.png` | The 4.2.3 defence, must stay first |
| `02-camera-lens-picker.png` | `app-settings-sheet.png` | Camera and lens picker |
| `03-rotation-leveling.png` | `app-settings-advanced.png` | Auto rotation, horizon levelling |
| `04-diagnostics.png` | `app-diagnostics.png` | Listener, fps, kbps, residual |

No device frames and no caption overlays were added: plain screenshots are allowed and a
fake frame risks 2.3.3. A separate 6.5" set was deliberately not produced. Apple auto-scales
from the 6.9" set, and 2796 x 1290 and 2778 x 1284 are not the same aspect ratio, so scaling
would distort rather than convert.

**New: an App Preview.** Section 3.5 did not plan one; it is worth having, because a
30-second video answers 4.2.3 before a reviewer has to read anything.
`~/Desktop/TetherCam-AppStore/app-preview-6.9-landscape.mp4` is a cut of the demo recording
from **0:05.0 to 0:34.5**, 29.5 seconds, 1920 x 886, H.264 High, yuv420p, 30 fps, stereo
AAC, faststart, 32 MB. The cut runs settings and lens picker, advanced settings and
diagnostics, the cable going into the Mac, the TetherCam source being added in OBS, and
five seconds of the live picture as the payoff.

Two decisions inside that encode are worth recording. The source recording is a 1920 x 1080
screen capture whose phone content occupies exactly the middle 1920 x 886, so a centred crop
would have been pixel-perfect. It was **not** used, because the source has no audio at all
(measured mean volume -91 dB) and the burned-in captions in the lower bar are therefore the
only explanation channel in the video. The full frame is scaled to 1576 x 886 and pillarboxed
to 1920 x 886 instead, which keeps the captions at the cost of black bars at the sides.
`app-preview-poster.png` (1920 x 886) is the intended poster frame, the OBS window with the
TetherCam source live; the poster is picked in the App Store Connect editor, not uploaded.

**Open owner decisions.** Whether to accept the pillarboxed preview or prefer a
caption-free full-bleed crop; whether to record a German-captioned variant later; and
whether to upload a German screenshot set once the interface is captured in German. None of
these blocks submission.
