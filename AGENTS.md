# Repository Guidelines

## Project Structure & Module Organization

CurveFan is a Swift Package Manager project for Apple Silicon fan control.

- `Package.swift` defines the package, targets, supported platform, and linked frameworks.
- `CurveFan/` contains `CurveFanCore`: SMC access, decoding, fan control, IPC models, presets, and shared domain types.
- `CurveFanApp/` contains the SwiftUI executable entry point and main UI.
- `CurveFanHelper/` contains the privileged helper executable for Unix socket IPC and SMC writes.
- `Tests/CurveFanTests/` contains XCTest coverage for fan curves, SMC decoding, keys, presets, and IPC protocol behavior.
- `setup.sh` and `uninstall.sh` install or remove local helper/app artifacts.

## Build, Test, and Development Commands

```bash
swift build
```

Builds all package targets in debug mode.

```bash
swift build -c release
```

Creates optimized release binaries.

```bash
swift test
```

Runs the XCTest suite.

```bash
bash build_app.sh release
sudo bash setup.sh
bash smoke_hardware.sh
```

Builds the app bundle, installs the privileged helper, and runs the hardware smoke test.

## Coding Style & Naming Conventions

Use Swift 6.4-compatible code and follow the existing style: 4-space indentation, concise types, and explicit boundary checks. Use `UpperCamelCase` for types such as `FanCurve`, `CurvePoint`, and `PresetManager`; use `lowerCamelCase` for properties, methods, and local variables. Keep platform, SMC, IPC, and UI concerns separated. Prefer small functions and avoid mixing helper privilege logic into UI code.

## Testing Guidelines

Tests use XCTest and should live under `Tests/CurveFanTests/`. Name methods with the `test...` prefix and cover one behavior or edge case per test. Favor deterministic tests for interpolation, validation, decoding, serialization, and IPC contracts. Hardware-dependent SMC access should be isolated behind abstractions and not required for `swift test`.

## Commit & Pull Request Guidelines

This checkout does not include Git history, so use a consistent Conventional Commits style:

```text
feat: add preset import support
fix: clamp fan curve RPM values
test: cover IPC decoding failure
```

Pull requests should include a short summary, verification results such as `swift test`, linked issues when applicable, and screenshots for UI changes. Call out changes that affect helper behavior, IPC contracts, setup scripts, or minimum macOS/Xcode requirements.

## Security & Configuration Tips

Treat SMC writes, privileged helper installation, and Unix socket IPC as high-risk areas. Do not commit credentials, local signing identities, generated build artifacts, or machine-specific paths. Validate all IPC inputs before issuing fan-control operations.
