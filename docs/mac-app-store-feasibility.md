# TetherCam for macOS on the Mac App Store — feasibility

Date: 2026-09-09. Scope: GitLab issue #15 (MAS) vs #14 (Developer ID .dmg).
Repo state referenced: `mac-app/` host (unsandboxed) + CMIO Camera Extension, verified
end-to-end with the simulator on 2026-09-09.
Host machine for the local evidence: macOS 26.6.2 (25G83), Xcode 26.0.1.

**Recommendation up front: ship `mac-app/` as Developer ID + notarized .dmg (#14).
The Mac App Store is blocked, and the blocker is not the camera extension — it is
`/var/run/usbmuxd`, which Apple's App Sandbox profile denies unconditionally, with no
entitlement escape and no public API replacement for USB app-to-app TCP.**

---

## 1. Can a sandboxed Mac App Store app talk to usbmuxd?

### 1.1 No. This is settled by Apple's own sandbox profile — **confidence: very high**

The sandbox profile that every App-Sandboxed application is compiled against contains an
explicit, *unconditional* deny for exactly this socket:

`/System/Library/Sandbox/Profiles/application.sb`, lines 751-752:

```scheme
(allow network-outbound (subpath "/private/var/run"))
(deny network-outbound (literal "/private/var/run/usbmuxd"))
```

Read those two lines together — this is the load-bearing detail. Apple **allows**
sandboxed apps to connect to UNIX-domain sockets under `/private/var/run` in general, and
then **carves out usbmuxd specifically**. This is not an accident of a coarse policy; it is
a deliberate, targeted block on exactly what `shared/usbmux.c` does.

Compare with the two neighbouring denies, which are *conditional* on an entitlement
(lines 756-762):

```scheme
(unless (entitlement "com.apple.security.print")
  (deny network-outbound (literal "/private/var/run/cupsd")))
(unless (or (entitlement "com.apple.security.network.client")
            (entitlement "com.apple.security.network.server"))
  (deny network-outbound (literal "/private/var/run/mDNSResponder")))
```

Apple knows how to write "deny unless entitled". For cupsd and mDNSResponder it did. For
usbmuxd it did not — **there is no entitlement, documented or undocumented, that unlocks
this line.** That is the single strongest piece of evidence in this report, and it is
first-party, on this machine, checkable in one grep.

The same deny appears in two more profiles:

| Profile | Line | Meaning |
|---|---|---|
| `application.sb` | 752 | every App-Sandboxed app (i.e. every MAS app) |
| `cmioextension.sb` | 209 | **every CMIO camera extension** — confirms the spec's "extension as receiver is impossible" |
| `container.sb` | 841 | containerized processes generally |

And, by contrast, Apple's *own* daemons get an explicit allow in their private profiles:

```
com.apple.cmio.iOSScreenCaptureAssistant.sb:20:  (literal "/private/var/run/usbmuxd")
com.apple.AssetCacheTetheratorService.sb:47:     (literal "/private/var/run/usbmuxd")
```

`iOSScreenCaptureAssistant` is the CoreMediaIO daemon behind wired iOS screen capture in
QuickTime/OBS. Apple reaches the phone over usbmuxd from a CMIO context — from a
**private, Apple-signed** profile that third parties cannot obtain. This is the clearest
possible statement of intent: usbmux is Apple-internal plumbing on the sandboxed side.

The socket's file permissions are *not* the gate — `srw-rw-rw- root daemon` on this Mac.
Anyone can connect; only the sandbox stops you. So there is nothing to fix with a
`temporary-exception.files.*` entitlement either (see 1.3).

### 1.2 `com.apple.security.network.client` does not help — **confidence: very high**

`appsandbox-common.sb` line 414 defines what that entitlement actually grants:

```scheme
(define (network-client)
  (system-network)
  (allow network-outbound (remote ip))
  ...)
```

`(remote ip)` — IP sockets only. It says nothing about AF_UNIX paths. The network
entitlements are orthogonal to the usbmuxd deny.

### 1.3 `com.apple.security.device.usb` is the wrong entitlement — **confidence: very high**

`application.sb` lines 119-123:

```scheme
(when (entitlement "com.apple.security.device.usb")
      (allow iokit-open-user-client
             (iokit-user-client-class "IOUSBDeviceUserClientV2" "IOUSBInterfaceUserClientV3")))
```

It grants IOKit USB user clients — raw USB device/interface access — and nothing else. It
has no relationship to the usbmuxd socket. And it would not help even conceptually: the
iPhone's USB interfaces are already claimed by the system's `AppleUSBMux` /
`usbmuxd` stack, so a third-party app cannot open them; on top of that you would have to
reimplement the lockdown/pairing (SRP, TLS) protocol yourself, which is undocumented.
*(IOKit-claim point: medium-high confidence — consistent across developer-forum threads,
no single authoritative Apple quote.)*

Docs: [App Sandbox entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html),
[`com.apple.security.device.usb`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb).

### 1.4 Apple DTS says the same thing, and closes the workarounds — **confidence: high**

Quinn (Apple DTS), [developer.apple.com/forums/thread/788364](https://developer.apple.com/forums/thread/788364):

> "Otherwise they are blocked by the sandbox as part of its general policy of blocking
> unmediated IPC between code from different teams."
>
> "You can't use a temporary exception entitlement to get around this because of both
> business and technical limitations: On the business side, App Review generally won't
> allow you to use temporary exception entitlements. On the technical side, entitlements
> like `com.apple.security.temporary-exception.files.absolute-path.read-write` only work
> for files and directories; **they don't work for Unix domain sockets**."
>
> "If you're targeting the Mac App Store then you can't use that option."

That kills the three obvious escapes in one paragraph: temporary-exception entitlements
(technically ineffective for sockets *and* rejected by review), and the
"non-sandboxed XPC helper" pattern (Developer-ID-only, since every executable in a MAS
bundle must itself be sandboxed).

### 1.5 Is any App Store app known to do it? — **confidence: medium-high (negative)**

No. The apps in TetherCam's exact shape all ship **outside** the MAS on the Mac side:

| App | Mac channel | iOS side |
|---|---|---|
| **Camo (Reincubate)** | direct .dmg only ([camo.com/downloads](https://camo.com/downloads)) | Camo Camera **is** on the iOS App Store |
| EpocCam (Elgato) | direct (discontinued) | App Store |
| OBS | direct, not MAS | — |
| `opendisplay` (OSS reference) | n/a | uses `NWListener` on the phone + **usbmuxd** on the Mac |

Camo is the strongest signal: same architecture as TetherCam (iOS capture app on the App
Store + Mac host publishing a virtual camera), and Reincubate ships the Mac host by direct
download. *(Absence of a counterexample is medium-high, not certain evidence; but it is
consistent with the sandbox profile, which is certain.)*

A second pass verified the wider category against the App Store search API
(`entity=macSoftware`) — **confidence: high**:

| Vendor / app | On the Mac App Store? |
|---|---|
| iMazing, AnyTrans, 3uTools, WALTR PRO | **No** — direct .dmg only |
| Camo Studio for Mac | **No** — `releases.reincubate.com/camo-macos-latest.dmg`. Note Reincubate *does* ship the Windows build via the Microsoft Store: they use first-party stores where they can, just not MAS |
| Duet Display, Luna Display, Astropad Studio (Mac hosts) | **No** — direct download; only the iOS/iPad halves are on the App Store |
| iMazing Profile Editor / Converter | Yes — but neither touches a device |
| Apple Configurator, Xcode | Yes — **Apple's own**, private entitlements; not a valid counterexample |

Unanimous: every third-party app that speaks usbmux ships Developer ID / direct, and no
vendor offers a cut-down "Lite" MAS build.

**Developer-side evidence — PeerTalk.** No vendor has published a "sandbox blocks usbmuxd"
statement, but PeerTalk (architecturally identical to TetherCam: Mac connects through
usbmux to a TCP listener in the iOS app) has it in the open —
[issue #36](https://github.com/rsms/peertalk/issues/36):

> "When I try to submit a Mac app that uses peertalk… I have to enable the sandbox.
> However, I get the **Operation Not Permitted** error because peertalk is no longer able
> to write to the device."

PeerTalk's README offers only one workaround, and it is a trap worth naming explicitly so
nobody re-discovers it: `com.apple.security.temporary-exception.sbpl` carrying
`(allow network-outbound (literal "/private/var/run/usbmuxd"))`. That key is
**undocumented**, Apple DTS advises against it
([forum 72330](https://developer.apple.com/forums/thread/72330)), and it has produced
documented App Store rejections
([electron#9757](https://github.com/electron/electron/issues/9757)). The README's old claim
that PeerTalk "has been released on the OS X app store (Duet Display)" is **stale** — Duet's
Mac app is not on MAS today.

### 1.6 Is there a public API for USB-tethered app-to-app TCP? — **No. Confidence: high**

The hypothesis in the brief ("Apple lists USB as a Bonjour-over-USB transport since
iOS 17 / macOS 14 via `NWParameters.includePeerToPeer`") **does not survive checking. It is
false on both halves.**

- `NWParameters.includePeerToPeer` is **iOS 12.0+ / macOS 10.14+**, not iOS 17 / macOS 14.
  Its documentation mentions no transport at all.
  [docs](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer)
- The authoritative enumeration is **TN3151 "Choosing the right networking API"**: "Apple
  platforms support **two peer-to-peer Wi-Fi technologies**: Wi-Fi Aware (NAN) and Apple
  peer-to-peer Wi-Fi… opt in by setting the `includePeerToPeer` property."
  **Both are Wi-Fi. USB/wired is never listed anywhere.**
  [TN3151](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)
- Wi-Fi Aware is not a fallback either: **macOS 26 does not support it**
  ([forum 787701](https://developer.apple.com/forums/thread/787701)).
- **Multipeer Connectivity**: deprecated in 2026; its "Ethernet" support means an ordinary
  LAN, not USB.
- **DeviceDiscoveryUI**: tvOS/Catalyst ↔ iOS/watchOS pairing for copies of the *same* app;
  system-brokered, not a wired transport.
  [docs](https://developer.apple.com/documentation/devicediscoveryui)
- **Continuity Camera wired** is driven by Apple's **private Rapport** framework
  (`ContinuityCaptureAgent`, `CMContinuityCaptureTransportRapportDevice`). Third parties may
  only *consume* the resulting `AVCaptureDevice`.
  [WWDC22 10018](https://developer.apple.com/videos/play/wwdc2022/10018/)

There are, however, **two real IP-over-USB links** between an iPhone and a Mac. They must
not be conflated:

**(a) "iPhone USB" / Personal Hotspot (CDC-NCM).** Real and present on this very Mac —
`networksetup -listallhardwareports` reports `Hardware Port: iPhone USB, Device: en8`
(currently `status: inactive`, no phone attached). This is an ordinary broadcast-capable
Ethernet-class interface, so **ordinary Bonjour + `NWListener`/`NWConnection` work over it
with public APIs and sandbox-legal entitlements**. Documented only as a *user* feature
([Apple Support](https://support.apple.com/en-euro/guide/mac-help/mchl7403f0ee/mac)), not
as a developer API. **Cost: the user must enable Personal Hotspot**, which is
cellular-plan-dependent and changes the Mac's routing. *Confidence that it works: medium —
plausible and consistent with all docs, but no shipping precedent found; this is spike
item 3.*

**(b) The iOS 16/17 `anpi` interface (`AppleUSBDeviceNCMPrivateEthernetInterface`).** A
second CDC-NCM interface that appears whenever a *trusted* iPhone is plugged in — no
hotspot, no cellular. Since iOS 17 it carries **RemoteXPC** (HTTP/2 + QUIC over IPv6
link-local), used by Xcode/CoreDevice; Apple's `remoted` advertises `_remoted._tcp` over
it, which is how `pymobiledevice3` discovers iOS 17+ devices. **So yes — mDNS demonstrably
traverses the USB link.** (Corroborating local observation: `dns-sd -B` on this Mac shows
`_remotepairing._tcp`, `_rp-tunnel._tcp`, `_remoted._tcp`.) **But** the interface name
literally contains *Private*, there is zero developer documentation, and there is **no
evidence and no API** for getting a *third-party* iOS `NWListener` advertised on it.
Treat as: **high confidence it is undocumented/private; low confidence it could be used.**
[Synacktiv](https://www.synacktiv.com/en/publications/ios-a-journey-in-the-usb-networking-stack) ·
[pymobiledevice3 RemoteXPC](https://github.com/doronz88/pymobiledevice3/blob/master/misc/RemoteXPC.md)

### 1.7 Local Network privacy applies either way — **confidence: high**

Per [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy):
a local network is "an IP network associated with a **broadcast-capable** interface…
Wi-Fi and Ethernet" — a USB-Ethernet link qualifies. Consequences:

- **"All Bonjour operations require local network access"** (register, browse, resolve).
- macOS **15+** enforces the Local Network TCC prompt (so macOS 26 does).
- Outgoing TCP to a local address requires the grant; **accepting** incoming TCP does not.
  Useful asymmetry: phone-listens / Mac-connects means only the Mac trips the prompt.
- iOS needs `NSLocalNetworkUsageDescription` (already present in `ios-app/project.yml`)
  **plus `NSBonjourServices`** listing the service type — that key is currently missing and
  would have to be added.
- Denial is detectable: `kDNSServiceErr_PolicyDenied` (-65570) or
  `NWPath.UnsatisfiedReason.localNetworkDenied`.

### 1.8 The other frameworks, and one nuance worth knowing

- **DeviceDiscoveryUI** — iOS/iPadOS/tvOS/Mac Catalyst 26 only, no native macOS, wireless
  pairing UI. Not applicable. **(high)**
- **ExternalAccessory** — nominally macOS 10.13+, but it is the MFi/iAP2 *accessory*
  framework; an iPhone cannot present itself as an MFi accessory. Wrong direction. **(high)**
- **MobileDevice.framework** — private, no headers, no SDK stub. **(high)**
- **Continuity Camera** — the only fully sanctioned public path, needs no entitlement, and
  is MAS-viable. But Apple owns codec, framing and lens selection, which is precisely what
  TetherCam exists to control. **(high)**
- **The nuance: the CoreMediaIO iOS *screen*-capture DAL device.**
  `kCMIOHardwarePropertyAllowScreenCaptureDevices` is in the **public SDK header**
  (`CMIOHardwareSystem.h`), requires no entitlement, and is mediated by the cmio daemon
  rather than by a raw socket — so it appears to **survive the sandbox**. Empirical
  support: *Phone Mirroring: Mirror to Mac* (id6753100395) and *Cargo • File Transfer for
  iOS* (id1612778232) are sandboxed MAS apps that reach an iPhone over USB, most likely via
  this DAL path and ImageCaptureCore/PTP respectively (**medium** — binaries not
  inspected; the header's default also needs re-checking on current macOS). It yields the
  phone's **screen mirror**, not a controllable camera pipeline with lens choice, rotation
  and audio — so it is a different product, not a transport substitute.

Finally, an Apple Media Engineer on the record
([forum 94744](https://developer.apple.com/forums/thread/94744)):

> "Using an iOS device's camera as an AVCaptureDevice on macOS is not a supported
> feature… If you want to capture frames from an iOS camera and preview them on a mac,
> **you'll need to beam them over yourself**, compressing them on the sending side and
> decompressing them on the receiving side."

That is a description of TetherCam's exact design — together with the implicit admission
that Apple ships no supported transport API for doing it.

**Answer to question 1: a sandboxed MAS app cannot reach usbmuxd (certain), no entitlement
changes that (certain), and there is no public API for USB app-to-app TCP (high
confidence). The only substantiable wired-but-public path is Personal Hotspot's
"iPhone USB" Ethernet link, which is a UX regression rather than a drop-in replacement.**

---

## 2. Can a MAS app embed and activate a CMIO Camera Extension?

### 2.1 Yes, explicitly and on the record — **confidence: high**

This is the pleasant surprise: the piece everyone assumes is the blocker is not.

WWDC22 session 10022, *"Create camera extensions with Core Media IO"*, verbatim:

> **"You can ship them as apps in the App Store."**
>
> **"This delivery mechanism is approved for App Store use, making it easy to deploy your
> camera extension to a wide audience."**

Same session, the other constraints — both of which TetherCam already satisfies or can:

> "System extensions can only be installed by apps residing in `/Applications`." — MAS
> installs to `/Applications` by definition, so this stops being a manual step (it is
> currently `mac-app/scripts/install-local.sh`'s job and a DMG "drag to Applications"
> instruction).
>
> "Your extension must be app sandboxed, or it won't be allowed to run." — already true:
> `mac-app/Extension/TetherCamCamera.entitlements` sets `com.apple.security.app-sandbox`.

[WWDC22 10022](https://developer.apple.com/videos/play/wwdc2022/10022/)

### 2.2 Entitlements — all MAS-allowed — **confidence: high (docs) / high (shipping proof)**

| Entitlement | Needed by | MAS status |
|---|---|---|
| `com.apple.developer.system-extension.install` | host | No "Developer ID only" note on the [entitlement page](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.system-extension.install); no request form; enabled via the Xcode capability |
| `com.apple.security.app-sandbox` | **host (new)** + extension | mandatory for MAS |
| `com.apple.security.application-groups` | both | standard |
| `com.apple.security.network.client` (+ `.server`) | host, for a network transport | standard |

Note the one real change to `mac-app/App/TetherCam.entitlements`: **the host would have to
become sandboxed**, which it deliberately is not today (`mac-app/project.yml` even
documents why). That is where the usbmux problem bites.

### 2.3 Shipping proof — two MAS apps do exactly this — **confidence: high**

- **Celluloid – Camera Filters** — [on the Mac App Store](https://apps.apple.com/us/app/celluloid-camera-filters/id6756587114?mt=12);
  the developer states it "uses Apple's CMIOExtension framework to register a virtual
  camera device with macOS", and v1.2.0 release notes add UI guidance for the manual
  Login Items & Extensions approval.
  [writeup](https://jakespurlock.com/2025/12/celluloid-a-virtual-camera-app-for-macos/)
- **Persona Webcam: Virtual Camera** (Nonstrict B.V.) —
  [Mac App Store](https://apps.apple.com/us/app/persona-webcam-virtual-camera/id6498891868),
  macOS 14+, version history references "improved guidance to enable the camera extension".

### 2.4 App Review Guidelines do not prohibit it — **confidence: high, with one caveat**

Guideline **2.4.5** (Mac technical requirements) names **kexts**, not system extensions,
and the extension ships *inside* the bundle, so 2.5.2 ("may not download, install, or
execute code") does not apply. Caveat (**medium** confidence): 2.4.5(ii)'s "cannot install
code or resources in shared locations" — a sysex *is* staged under
`/Library/SystemExtensions`, but that is Apple's own framework doing it, and the two
shipping apps above prove review accepts it.
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

### 2.5 No alternative virtual-camera mechanism exists — **confidence: high**

DAL plug-ins were deprecated in macOS 12.3 and **removed in macOS 14.1**
([Apple support doc](https://support.apple.com/en-us/108387)). There is no public API to
register a capture device other than CMIOExtension. So the extension is not optional — but
it is also not the problem.

**Answer to question 2: yes. Camera extension + MAS is a solved, shipping combination.**

---

## 3. Architecture for a MAS-compliant TetherCam Mac app

### 3.1 The honest framing

There is no architecture that is *both* MAS-compliant *and* USB-over-usbmux. Sections 1
and 2 together mean:

> **The Mac App Store version cannot be the same product.** It must give up the cable
> (or give up the "no Personal Hotspot" promise). The USB story — the entire premise in
> `CLAUDE.md`, "ohne WLAN" — is exactly what the sandbox forbids.

So this is a product decision before it is an engineering one. Three options:

| Option | Transport | Keeps the USB promise | MAS | Verdict |
|---|---|---|---|---|
| **A. Developer ID .dmg** (#14) | usbmux, unchanged | yes | no | **Recommended.** Zero new risk, existing notarization pipeline, same channel as Camo and OBS |
| **B. MAS + local-network (Wi-Fi) transport** | Bonjour + TCP over LAN | **no** | yes | Viable but it is a *different product*: a Wi-Fi camera, competing with a crowded field, without the differentiator |
| **C. MAS + "iPhone USB" Personal Hotspot link** | Bonjour + TCP over the CDC-NCM interface | partly (cable, but Hotspot must be on) | yes | Interesting; unproven; spike item 3 |
| **D. MAS + CoreMediaIO screen-capture DAL** | cmio daemon, no socket | yes (cable) | yes | Sandbox-viable and needs **no companion app at all** — but it mirrors the phone's *screen*, so no lens choice, no rotation policy, no audio. A different product; worth knowing exists (§1.8) |

B and C share **all** their code. The transport is one `Endpoint` case; whether the packets
travel over Wi-Fi or the hotspot Ethernet link is a runtime accident. That is the good
news: **do B, and C comes free if the spike says the interface behaves.** Ship B/C as a
*separate* MAS product (e.g. "TetherCam Wireless") and keep A as the flagship.

### 3.2 What changes in `protocol/PROTOCOL.md` — **less than you'd think, but not nothing**

The framing is already transport-agnostic: §1 *Transport* is cleanly separated from §2
*Rahmung*, and §1 already sanctions "dasselbe Protokoll ueber eine gewoehnliche
TCP-Verbindung". Messages, PTS handling, and the audio rules are untouched.

Two changes are genuinely required, and one of them is a security change that must not be
skipped:

1. **§1: add the Bonjour/LAN transport** — service type `_tethercam._tcp`, TXT record with
   a protocol-version key, note that the framing from §2 applies unchanged from the first
   byte after `accept()`.
2. **A pairing/authentication step — new, and mandatory for B/C.** Over usbmux the
   listener is unreachable except through the cable, so "no auth" was defensible. On a
   LAN, `NWListener` on 7878 is reachable by **every device on the network**, and the
   payload is the user's camera and microphone. This needs a shared secret: a 6-digit code
   shown on the phone, entered on the Mac, and an authenticated HELLO/START (e.g. HMAC over
   a server nonce). Bump to protocol 1.2 and gate it behind the START flags byte.
   **This is the largest single piece of new work and the biggest source of new bugs.**
   TLS via `NWProtocolTLS` with a PSK derived from the pairing code is the cheap way to get
   both auth and confidentiality in one step.

### 3.3 What changes in the iOS app

- **Keep `ios-app/Sources/Server/UsbServer.swift`'s port-7878 `NWListener` exactly as is.**
  It already serves the OBS plugin and any usbmux client, and the same listener socket can
  simultaneously be advertised over Bonjour — one listener, two discovery paths, no second
  accept loop, no BUSY-semantics change (§1's "genau ein Empfaenger" still holds naturally).
- Add the Bonjour advertisement: `NWListener.service = NWListener.Service(name:, type:
  "_tethercam._tcp")`. Roughly a 10-line change in `start()`.
- `ios-app/project.yml`: add **`NSBonjourServices = ["_tethercam._tcp"]`**. The
  `NSLocalNetworkUsageDescription` string is already there but its text ("Local listener on
  TCP 7878 for the USB connection to the Mac.") would need rewording — and the German
  string too.
- Pairing UI: display the code, show which Mac is connected, allow revoke.
- Do **not** set `includePeerToPeer` — per §1.6 it buys AWDL/Wi-Fi, not the cable, and it
  costs battery.

### 3.4 What changes in `mac-app`

- `mac-app/Core/Sources/TetherCamCore/Receiver/Transport.swift`: the `Endpoint` enum
  (currently `.tcp(host:port:)` and `.usbmux(serial:)`) gains **`.bonjour(name: String?)`**.
- The implementation fits the existing design better than it might look. `Receiver.swift`
  runs a blocking thread over a raw `Int32` fd, and `Transport.connectTCP` already does
  `getaddrinfo` + `connect`. So the Bonjour case can be: `NWBrowser` → resolve to
  `host.local` + port → hand the name straight to the existing `connectTCP`. **No rewrite of
  the receiver loop, no async/await migration, no second framer.** (Binding the connection
  to a specific interface index, if the hotspot path is used, is the one extra wrinkle.)
- `mac-app/App/TetherCam.entitlements`: add `com.apple.security.app-sandbox` and
  `com.apple.security.network.client`; keep `system-extension.install` and the app group.
- `mac-app/project.yml`: remove the "deliberately NOT sandboxed" comment and its rationale.
- Local Network TCC: handle `localNetworkDenied` in the `LinkState` machine — a new user-
  visible state next to `no-device`/`waiting`, with a button to the Settings pane (the
  `ExtensionInstaller` already has that pattern for camera-extension approval).
- `tools/vcam-test.sh` and `usbcam-sim` keep working unchanged via `--debug-tcp`.

### 3.5 Risks

| # | Risk | Severity | Notes |
|---|---|---|---|
| 1 | **Sandboxed host may not be able to feed the CMIO sink** | **critical, unknown** | `CMIOStreamCopyBufferQueue` + the app-group mach-lookup from a *sandboxed* host is untested. `cmioextension.sb:62` allows `(application-group-regex suite "/")` on the extension side, but the host side is unproven. **If this fails, MAS is dead regardless of transport.** Spike item 1. |
| 2 | Guideline **2.1** — reviewer cannot test it | high | Needs an iPhone, the companion app, a cable/LAN, *and* a manual extension approval. Mitigate with Review Notes + demo video, as `docs/app-store/` already does for iOS. |
| 3 | Guideline **4.2** minimum functionality | medium | The app does nothing without the phone. Same mitigation. |
| 4 | Two manual gates | medium | Extension approval (admin password, not automatable) *plus* the Local Network prompt *plus* pairing. First-run friction goes up, not down — and the spec already flags first-run friction as risk 4. |
| 5 | New auth surface | medium-high | §3.2 item 2. A camera stream on an open LAN is a genuine privacy defect; get this reviewed. |
| 6 | Existing spec risk 5 (sink authorization) becomes worse | medium | `CMIOExtensionClient.signingID` was nil for the Apple-Development-signed host; a MAS-signed host is a third signing context to re-test. |
| 7 | Personal Hotspot dependency (option C only) | high | Cellular-plan-dependent, changes Mac routing, confusing to explain. |
| 8 | Product dilution | medium | Two Mac apps to maintain, two support stories, and the MAS one is the *weaker* product. |

No documented App Review rejection *caused by* a bundled camera extension was found
(medium confidence — absence of evidence).

---

## 4. Effort and the 1-day spike

### 4.1 Estimate (experienced Swift developer, calendar days)

| Path | Days | Notes |
|---|---|---|
| **A. Developer ID .dmg** (#14) | **2-3** | Signing/notarization/stapling, DMG layout, Homebrew cask. Pipeline already exists in `scripts/`. |
| **B/C. MAS build** | **12-17** + review | breakdown below |

MAS breakdown:

- Spike (§4.3) — **1**
- Sandbox the host; fix every resulting denial; re-verify the CMIO sink path — **2-3**
- Bonjour transport, both sides (`.bonjour` case, browser, advertisement, interface
  binding) — **3-4**
- Pairing + PSK-TLS, protocol 1.2, both sides, `protocol/PROTOCOL.md`, fixtures, tests — **3-4**
- Local Network TCC states + first-run UX + Settings deep links — **1**
- ASC record, sandboxed provisioning profile, metadata, screenshots, review notes,
  demo video — **2**
- Contingency for App Review rounds — **not estimable; assume ≥1 rejection cycle.**

### 4.2 Unknowns only a spike can answer

1. **Can a *sandboxed* host still open the extension's sink stream and push frames?**
   (Risk 1. Everything else is wasted effort if this is no.)
2. Does the sandboxed host survive the rest of its work — VideoToolbox decode,
   `VTPixelTransferSession`, app-group container — without new denials?
3. Does the **iPhone-USB / hotspot interface (en8)** actually carry third-party Bonjour,
   and does it work with **Wi-Fi switched off**? (Decides whether option C exists at all.)
4. Does the hotspot interface come up without an active cellular data plan?
5. Does the Local Network TCC prompt appear correctly for a sandboxed menu-bar
   (`LSUIElement`) app, which has no Dock icon to attach the prompt to?
6. Is `CMIOExtensionClient.signingID` still nil under a MAS/Developer-ID signature
   (spec risk 5)?

### 4.3 Concrete 1-day spike plan

**Kill-switch order — stop at the first failure. Items 1 and 3 are the whole point.**

**Step 1 (2h) — Sandboxed host → CMIO sink. The go/no-go.**
Add `com.apple.security.app-sandbox` + `com.apple.security.network.client` to
`mac-app/App/TetherCam.entitlements`, keep the app group and `system-extension.install`.
Build Release, install to `/Applications`, run against the simulator on loopback:

```bash
tools/.build/release/usbcam-sim --bind 127.0.0.1 --port 7878 --no-audio &
/Applications/TetherCam.app/Contents/MacOS/TetherCam --debug-tcp 127.0.0.1:7878 --headless
```

- **Proves success:** a status line with **`pushed=` greater than 0**, e.g.
  `tethercam: link=streaming camera=ready res=1920x1080@30 fps=30 pushed=113 dropped=38`.
  `pushed>0` is the only trustworthy signal — `vcam-test.sh` already learned that the
  placeholder animation otherwise fakes a pass.
- **Proves failure:** `camera=error`, `pushed=0` while `link=streaming`, or any line from
  `log stream --predicate 'sender == "Sandbox"' --style compact` naming `TetherCam`.
- Then run the full `bash tools/vcam-test.sh` for the independent ffmpeg/PSNR check.
- **If this fails: stop. Write "MAS impossible, sandboxed host cannot drive the sink" into
  #15 and close it in favour of #14.**

**Step 2 (1h) — Confirm the usbmux deny empirically.** Run the same sandboxed build with
the real phone on the normal `.usbmux` endpoint. This step is designed to *fail*, and the
failure is the deliverable — it converts §1.1 from "profile says so" to "measured here".

- **Proves the point:** `connect()` fails with `EPERM`, and
  `log stream --predicate 'sender == "Sandbox"'` shows
  `deny(1) network-outbound /private/var/run/usbmuxd` for the TetherCam pid.
- **Would overturn the report:** `link=streaming`. (Do not expect it.)

**Step 3 (3h) — Bonjour over the cable, with Wi-Fi off. Decides option C.**
Add ~10 lines to `UsbServer.start()` advertising `_tethercam._tcp`, plus `NSBonjourServices`
in `ios-app/project.yml`. Install to the iPhone, plug in the cable, enable Personal Hotspot,
confirm `ifconfig en8` flips from `status: inactive` to `status: active`, then **turn the
Mac's Wi-Fi off** and:

```bash
dns-sd -B _tethercam._tcp local        # must list the service
dns-sd -L "<instance>" _tethercam._tcp # must resolve to a host + port 7878
nc -vz <host>.local 7878               # must connect
```

- **Proves success:** the service resolves **with Wi-Fi off**, on the interface index of
  `en8` (`python3 -c "import socket;print(socket.if_nametoindex('en8'))"`), and the existing
  `usbcam-recv` tool pulls a decodable stream over it.
- **Proves failure:** nothing on `en8` with Wi-Fi off, or the service only appears when
  Wi-Fi is on → **option C does not exist**; MAS means Wi-Fi-only (option B), and the
  product question in §3.1 has to be answered by the owner before any more code.

**Step 4 (1h) — Write up.** Append a dated correction to
`docs/superpowers/specs/2026-09-09-virtual-camera-cmio.md` (its "Non-goals (v1) → Mac App
Store" bullet currently says only "that is its own issue"; it can now say *why*, with the
`application.sb:752` citation). Update #15 with the go/no-go.

---

## Sources

Local, first-party, verifiable on this machine (macOS 26.6.2):
`/System/Library/Sandbox/Profiles/application.sb:751-752`,
`cmioextension.sb:62,209,215`, `container.sb:841`,
`appsandbox-common.sb:414`, `application.sb:119-123`,
`com.apple.cmio.iOSScreenCaptureAssistant.sb:20`,
`com.apple.AssetCacheTetheratorService.sb:47`;
`ls -l /var/run/usbmuxd`; `networksetup -listallhardwareports`; `dns-sd -B`.

Apple: [WWDC22 10022 camera extensions](https://developer.apple.com/videos/play/wwdc2022/10022/) ·
[WWDC22 10018 Continuity Camera](https://developer.apple.com/videos/play/wwdc2022/10018/) ·
[TN3151](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api) ·
[TN3179 local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) ·
[includePeerToPeer](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer) ·
[system-extension.install](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.system-extension.install) ·
[App Sandbox entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) ·
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) ·
[DeviceDiscoveryUI](https://developer.apple.com/documentation/devicediscoveryui) ·
[DAL removal in 14.1](https://support.apple.com/en-us/108387) ·
[iPhone USB network service](https://support.apple.com/en-euro/guide/mac-help/mchl7403f0ee/mac) ·
Forums [788364 (Quinn, sandbox + UNIX sockets)](https://developer.apple.com/forums/thread/788364),
[718461](https://developer.apple.com/forums/thread/718461),
[769043](https://developer.apple.com/forums/thread/769043),
[787701](https://developer.apple.com/forums/thread/787701),
[736838](https://developer.apple.com/forums/thread/736838)

Third-party: [Celluloid on MAS](https://apps.apple.com/us/app/celluloid-camera-filters/id6756587114?mt=12) ·
[Celluloid writeup](https://jakespurlock.com/2025/12/celluloid-a-virtual-camera-app-for-macos/) ·
[Persona Webcam on MAS](https://apps.apple.com/us/app/persona-webcam-virtual-camera/id6498891868) ·
[Camo downloads](https://camo.com/downloads) ·
[Synacktiv: iOS USB networking stack](https://www.synacktiv.com/en/publications/ios-a-journey-in-the-usb-networking-stack) ·
[pymobiledevice3 RemoteXPC](https://github.com/doronz88/pymobiledevice3/blob/master/misc/RemoteXPC.md) ·
[pymobiledevice3 iOS 17 tunnels](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/) ·
[libimobiledevice/usbmuxd](https://github.com/libimobiledevice/usbmuxd) ·
[opendisplay](https://github.com/peetzweg/opendisplay) ·
[ManyCam camera extension](https://help.manycam.com/knowledge-base/macos-camera-extension/) ·
[PeerTalk issue #36 (sandbox → Operation Not Permitted)](https://github.com/rsms/peertalk/issues/36) ·
[electron#9757 (sbpl temporary exception → App Store rejection)](https://github.com/electron/electron/issues/9757) ·
Forums [72330 (DTS on temporary-exception.sbpl)](https://developer.apple.com/forums/thread/72330),
[94744 (Apple Media Engineer: "you'll need to beam them over yourself")](https://developer.apple.com/forums/thread/94744) ·
[Camo macOS download](https://releases.reincubate.com/camo-macos-latest.dmg)

## Addendum 2026-09-09 (spike run the same evening, details on GitLab #15, #17, #18)

- **Sandbox + usbmuxd is measured, not assumed.** The same C binary connects to
  `/var/run/usbmuxd` as a plain executable and fails with `errno=1 Operation not permitted`
  inside a signed `.app` carrying `com.apple.security.app-sandbox`. No entitlement lifts it.
- **A sandboxed host CAN feed the camera extension's sink**, contrary to the earlier risk
  estimate, but only with `com.apple.security.device.camera`. Without that entitlement the
  sandboxed host sees no camera devices at all and fails silently (`camera=error pushed=0`,
  no `deny` line in the log). With it: `camera=ready`, frames flow. So the host + extension
  architecture survives the sandbox; only the USB transport does not.
- Follow-ups: #17 (Bonjour-over-cable transport spike, needs a phone), #18 (spec: the
  extension can never own usbmux under any channel, host-bridged is the only design).
