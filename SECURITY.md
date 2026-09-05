# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x | Yes |
| older | No |

TetherCam is pre 1.0. Only the latest 0.1.x line receives security fixes.

## What is in scope

TetherCam's Mac side opens no network listener at all. The OBS plugin talks to the phone
through a local usbmux TCP tunnel to port 7878 on the phone; that port is only reachable
through the USB cable and `usbmuxd`, never over Wi-Fi or a public interface. In scope for
security reports:

- The frame parser in `shared/` that decodes the IUCM wire protocol (`protocol/PROTOCOL.md`).
  It is fuzzed, but a parser bug that survives fuzzing is still worth a report.
- The usbmux client in `shared/` and its use of `/var/run/usbmuxd`.
- The OBS plugin's handling of data received over the usbmux tunnel.
- The iOS app's TCP server on port 7878 and its handling of incoming connections.

Out of scope: issues that require an attacker to already have a shell on the Mac or a
jailbroken/compromised phone, and social engineering.

## Reporting a vulnerability

Please do not open a public issue for security problems.

- Preferred: use GitHub private vulnerability reporting on this repository (Security tab,
  then "Report a vulnerability").
- Alternative: email venturestudio@ai-at.eu with details and, if possible, a way to
  reproduce the issue.

We aim to respond within 7 days and to agree on a disclosure timeline with you before any
public write up.
