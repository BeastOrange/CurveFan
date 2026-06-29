# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift build                              # Debug build, all targets
swift build -c release                   # Release binaries
swift build --product CurveFanHelper     # Build a single product
swift test                               # Run the XCTest suite (no hardware required)
swift test --filter FanCurveTests        # Run one test class
swift test --filter FanCurveTests/testInterpolation   # Run one test method
bash build_app.sh release                # Bundle .build/release/CurveFan.app (builds first, generates .icns)
sudo bash setup.sh                       # Install helper daemon + app to /Applications
bash setup.sh --check                    # Report installed helper/socket/app status
bash smoke_ipc_local.sh                  # End-to-end IPC test against a fake-SMC helper (no hardware, no sudo)
bash smoke_hardware.sh                   # IPC test against the installed helper on real hardware
sudo bash uninstall.sh [--keep-data]     # Remove all installed artifacts
```

Toolchain: Swift 6.4, platform `.macOS(.v26)`, Apple Silicon only. `swift test` never touches hardware — keep it that way.

## Three-process architecture

The app is split into three SwiftPM targets defined in `Package.swift`. Understanding the privilege boundary between them is the key to working here.

- **CurveFanCore** (`CurveFan/`) — a library target shared by both executables. Contains all domain models, the SMC abstraction, IPC types, fan-curve math, and presets. Links IOKit. This is where most logic lives.
- **CurveFan** (`CurveFanApp/`) — the SwiftUI executable. Runs unprivileged as the user. Never touches the SMC directly; it talks to the helper over a Unix socket.
- **CurveFanHelper** (`CurveFanHelper/Sources/main.swift`) — a privileged LaunchDaemon (`com.curvefan.helper`, runs as root). The **only** process that opens the SMC and performs reads/writes.

Data flow for any hardware operation: `AppState` → `FanController`/`TemperatureReader` → `IPCClient` → Unix socket → helper `handleCommand` → `SMCService`/IOKit. The app and helper communicate with `IPCCommand`/`IPCResponse` (`CurveFan/Models/IPCTypes.swift`) serialized as JSON inside a length-prefixed frame (`IPCFraming`: 4-byte big-endian length + payload, max 1 MiB).

Because both executables depend on CurveFanCore, the wire types and framing logic are shared by construction — change `IPCTypes.swift` or `IPCFraming.swift` and both ends update together. Keep them in sync; a divergence breaks IPC silently.

## SMC access layer

- `SMCService` (`CurveFan/Services/SMC.swift`) — raw IOKit `AppleSMC` calls (read/write/getKeyInfo). Helper-side only.
- `SMCDecoder` (`CurveFan/Services/SMCDecoder.swift`) — pure byte ↔ `Double` conversion for SMC four-char data types (`sp78`, `fpe2`, `flt`, `ui8/16/32`, `si8`). Fully unit-testable, no hardware. This is the right place to add new data-type support.
- `SMCKeyDB` (`CurveFan/Models/SMCKeys.swift`) — static database of known fan and temperature keys, tagged by `ChipGen` (M1–M5) and writability. `TemperatureReader` queries it per detected chip; the helper uses it to resolve writable fan-mode keys.

### Chip-generation branching

`ChipGen.current()` detects the SoC from `machdep.cpu.brand_string`. Fan-mode control differs by generation and several code paths branch on it — when adding hardware support, check all of these:
- Fan-mode SMC key casing: `F%dMd` (M1–M4) vs `F%dmd` (M5). See `SMCKeyDB.writableFanModeKey` and the helper's `modeKey(for:)`, which probes both.
- Unlock sequence (helper `unlockFanControl`): M5 sets manual mode directly; M1–M4 first write the `Ftst` diagnostic-unlock key, poll until mode leaves `system`, then set manual. `restoreFanControl` mirrors this (clears `Ftst` on non-M5).
- Temperature key sets differ sharply per generation (M1/M2, M3, M4/M5) — see the three private arrays in `SMCKeyDB`.

## Safety-critical: restoring auto fan control

Manual fan control is a thermal risk, so the code restores macOS auto control aggressively. When editing lifecycle, polling, or fan-control code, preserve every restore path:
- App quit / `willTerminate` → `AppState.restoreAutoForShutdown()` stops curve control and restores **all** fans.
- Selecting the **Auto** preset or `System Auto` → `restoreAuto(fan:)`.
- Helper `SIGTERM`/`SIGINT` → `cleanup()` restores all fans before exit (defense in depth if the app dies).
- `FanController.observeWakeEvents()` re-applies manual RPM after system wake (the SMC resets to auto on sleep).

## Helper security model

The helper accepts connections only from authorized peers — `isAuthorizedPeer` checks `LOCAL_PEERCRED`, allowing root, the helper's euid, or the console user. The socket is `chown`ed to the console user (mode 0600). The helper validates every input before acting: `validateSMCKey` (1–4 printable-ASCII bytes), `validateFanIndex` (against live `FNum`), and RPM clamping to the fan's reported `min...max`. Maintain this validation when adding commands — the helper runs as root.

## Testing notes

- The helper honors `CURVEFAN_HELPER_FAKE_SMC=1` to serve canned SMC values (see `fakeReadKey`/`fakeReadKeyData` in `main.swift`), and both helper and `IPCClient` honor `CURVEFAN_SOCKET_PATH` to override the socket location. `smoke_ipc_local.sh` uses both to run a full IPC round-trip with no hardware or sudo.
- Keep hardware-dependent logic behind `SMCService` so `swift test` stays deterministic. Tests cover curve interpolation/validation, SMC decoding, key DB, presets, and IPC framing/protocol.

## Conventions (from AGENTS.md)

4-space indentation; `UpperCamelCase` types, `lowerCamelCase` members; keep platform/SMC/IPC/UI concerns separated and helper-privilege logic out of UI code. Commits follow Conventional Commits (`feat:`, `fix:`, `test:`). Call out any change touching helper behavior, IPC contracts, setup scripts, or the minimum macOS/Xcode requirement.
