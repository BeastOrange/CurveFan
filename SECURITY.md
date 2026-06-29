# Security Policy

## Why security matters here

CurveFan runs a privileged helper (`curvefan-helper`) as root that writes directly to the System Management Controller (SMC) to control fan speed. A vulnerability in the IPC layer between the app and the helper could allow an unprivileged process to manipulate fan hardware. This document explains the threat model, the defenses already in place, and how to report a security issue.

## Supported versions

Only the latest release receives security fixes. Older releases are not patched.

## Threat model

| Threat | Defense |
|--------|---------|
| Unprivileged local process sends commands to the helper socket | Socket is `chown`ed to the console user (mode 0600); helper checks `LOCAL_PEERCRED` before processing any command |
| Malformed IPC input causes undefined behavior in the helper | All inputs are validated before use (see below) |
| Fan set to 0 RPM / unsafe value, causing thermal damage | RPM values are clamped to the fan's hardware `minRPM`–`maxRPM` range; values outside that range are rejected |
| Helper process keeps manual fan control after app crashes | Helper restores macOS automatic fan control on `SIGTERM`/`SIGINT`; app restores on quit |
| SMC key injection via crafted key strings | Key names are validated: 1–4 bytes, printable ASCII only |

## IPC security details

The helper listens on a Unix domain socket at `/var/run/curvefan-helper.socket`.

**Peer authorization** (`isAuthorizedPeer` in `CurveFanHelper/Sources/main.swift`): each accepted connection has its credentials checked via `getsockopt(LOCAL_PEERCRED)`. Only three UIDs are accepted: `root` (uid 0), the helper's own effective UID, and the current console user. All other connections are closed immediately without reading any data.

**Input validation** before any SMC operation:
- `validateSMCKey`: rejects keys that are not 1–4 printable ASCII bytes.
- `validateFanIndex`: rejects fan indices outside 0…(fanCount−1), where fanCount is read live from SMC.
- RPM bounds check in `writeFanRPM`: the requested RPM must equal its clamped value; anything outside the fan's reported range returns an error rather than writing.

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately via one of:
- GitHub private vulnerability reporting: go to the repository → Security tab → "Report a vulnerability"
- Email: beastorange253@gmail.com

Please include:
- A description of the vulnerability and its potential impact
- Steps to reproduce
- Your macOS version and Apple Silicon chip generation (M1/M2/M3/M4/M5)
- Whether the issue is in the app, the helper, or the IPC protocol

We will acknowledge receipt within 72 hours and aim to release a fix within 14 days for critical issues.

## Known limitations

- The helper binary is currently **unsigned** (pre-1.0 release). This means it must be installed manually via `sudo bash setup.sh` rather than through a sandboxed mechanism. Code signing and notarization are planned before a public release.
- The Unix socket has no rate limiting. Rapid repeated connections from an authorized UID are not throttled.
- Fan control is not sandboxed at the OS level beyond the `LOCAL_PEERCRED` check described above.
