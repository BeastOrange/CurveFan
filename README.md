# CurveFan

CurveFan is a native macOS menu bar app for monitoring temperatures and controlling Apple Silicon Mac fan speed. It uses a privileged helper for SMC access, keeps the menu bar UI lightweight, and restores macOS automatic fan control when you choose **System Auto** or quit the app.

> CurveFan writes fan control values through a privileged helper. Use it only if you understand the thermal risk of manual fan control.

## What CurveFan does

- Shows current fan RPM, fan mode, and CPU/GPU temperatures from the menu bar.
- Restores macOS system fan control with **System Auto**.
- Applies built-in fan curve presets: **Quiet**, **Balanced**, and **MaxCool**.
- Supports a fixed manual RPM target when you need direct control.
- Runs SMC writes through a LaunchDaemon helper instead of the UI process.

## Requirements

- Apple Silicon Mac with at least one controllable fan
- macOS 26.0 or newer, matching the package platform setting
- Swift 6.4 / Xcode command line tools for building from source
- Administrator access for installing the privileged helper

## Build from source

Clone the repository:

```bash
git clone git@github.com:BeastOrange/CurveFan.git
cd CurveFan
```

Build the Swift package:

```bash
swift build
```

Run the test suite:

```bash
swift test
```

Build the release app bundle:

```bash
bash build_app.sh release
```

This creates:

```text
.build/release/CurveFan.app
```

## Install locally

Install the helper daemon and copy the app to `/Applications`:

```bash
sudo bash setup.sh
```

Check the installed helper and socket:

```bash
bash setup.sh --check
```

If macOS blocks the unsigned local build, clear quarantine:

```bash
sudo xattr -cr /Applications/CurveFan.app
```

Then open:

```bash
open /Applications/CurveFan.app
```

## Verify hardware access

After installing the helper, run:

```bash
bash smoke_hardware.sh
```

To also restore macOS automatic fan control at the end of the smoke test:

```bash
CURVEFAN_SMOKE_RESTORE=1 bash smoke_hardware.sh
```

## Uninstall

Remove the app, helper binary, LaunchDaemon, and user data:

```bash
sudo bash uninstall.sh
```

Keep presets and local data:

```bash
sudo bash uninstall.sh --keep-data
```

## Project structure

```text
CurveFan/           Core models, SMC access, IPC, presets, and fan control
CurveFanApp/        SwiftUI menu bar app
CurveFanHelper/     Privileged helper daemon for SMC reads and writes
Scripts/            Local IPC utility scripts
Tests/              XCTest coverage for curves, SMC decoding, keys, and IPC
local-docs/         Local product and design notes
```

## Safety notes

- **System Auto** restores fan control to macOS.
- Quitting CurveFan restores automatic fan control before termination.
- Manual RPM and curve presets intentionally write fan control values.
- Hardware smoke tests should be run only on supported Apple Silicon Macs.

## License

CurveFan is released under the MIT License. See [LICENSE](LICENSE).
