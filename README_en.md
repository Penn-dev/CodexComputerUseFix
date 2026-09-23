# Codex Capture Compat

[简体中文](README.md) | [English](README_en.md)

A Windows compatibility layer for Codex Computer Use. It builds a local x64 `version.dll` for Windows 10 capture-interface and callback issues, and provides a reversible target-window guard for releases that can return Codex or another foreground window after a different target was selected.

After installation, use Computer Use as usual. No separate proxy process or additional MCP service is required. This is an independent compatibility implementation and does not include the official helper's source code.

## Features

- **Capture border compatibility:** Handles `IsBorderRequired` property calls when the system lacks `IGraphicsCaptureSession3`, preserving the default Windows capture border.
- **Screenshot callback dispatch:** Sends eligible `FrameArrived` callbacks to MTA workers in the Windows thread pool, avoiding blocking waits for image conversion inside Windows Graphics Capture (WGC) callbacks.
- **Target-window guard:** Activates and rehydrates the requested window before `get_window_state`, working around the official Windows helper's known wrong-window screenshot behavior.
- **CU proxy environment injection:** Initializes Node's local HTTP proxy before importing `cua_repl`, addressing `nodeRepl.fetch request failed` in proxied environments. Loopback destinations remain excluded.
- **Local installation and removal:** Installs the DLL and an installation record beside the helper. Removal verifies the recorded path and DLL hash.
- **Development tools:** Includes COM unit tests, a probe for real WGC capture, a standalone test window, and optional call tracing.

The project targets Windows 10 x64. Compatibility hooks are enabled for `codex-computer-use.exe` and the test program `compat_probe.exe`. Changes are confined to processes that load the DLL; system DLLs are not modified and no global hooks are registered.

## Download a prebuilt release

Download `CodexCaptureCompat-<version>-windows-x64.zip` from [GitHub Releases](https://github.com/MagicalAstrogy/CodexComputerUseFix/releases). Extract the complete archive, then follow the usage instructions below. No compiler toolchain is needed. Archives with a `-trace` suffix are diagnostic builds; use the regular build for everyday operation.

Each ZIP has a `.sha256` checksum file and includes the installer, probes, documentation, and source. See the [CI and release guide](capture-compat/docs/ci_en.md) for verification and publishing instructions.

## Build from source

Open PowerShell in the project root:

```powershell
Set-Location .\capture-compat
.\build.ps1
.\tests\install_tests.ps1
.\validate.ps1
Set-Location ..
.\window-target-guard\tests\install_tests.ps1
.\proxy-env\tests\install_tests.ps1
```

Building requires the MSVC x64 C++ tools, MASM, and the Windows SDK. Live capture tests require a logged-in, unlocked Windows 10 interactive desktop. See the [build and usage guide](capture-compat/README_en.md) for toolchain requirements and build options.

Build outputs are written to `capture-compat/dist/`:

| Artifact | Purpose |
| --- | --- |
| `version.dll` | Compatibility layer to install beside the Computer Use helper |
| `compat_probe.exe` | Tests the border interface, real capture, and asynchronous callbacks |
| `capture_test_window.exe` | Standalone window for testing screenshots through Computer Use |

Building and running the probe do not automatically install or update the DLL in the runtime directory.

## Usage

### Status, installation, and update monitoring

`manage.ps1` in the repository root is the unified entry point. It is not a resident service and does not call a model:

```powershell
.\manage.ps1 status
.\manage.ps1 install
.\manage.ps1 uninstall
.\manage.ps1 monitor-install
.\manage.ps1 monitor-uninstall
```

`status` locates the latest Codex Computer Use runtime and reports the capture compatibility DLL, target-window guard, CU proxy environment, and Windows native CU routing separately. It also reads the state of the related public `openai/codex` issues by default; a network failure is reported as `unavailable` and does not block local checks.

`monitor-install` creates a per-user scheduled task that runs at sign-in and daily at 10:00. `StartWhenAvailable` catches a missed scheduled time, while the state file limits network checks to once per day. It only notifies when the runtime, owned patch, routing configuration, or open/closed state of a related issue changes. It never installs, removes, or modifies Codex automatically. `monitor-uninstall` removes the task. State and logs are stored under `%LOCALAPPDATA%\CodexComputerUseFix`.

`official-path-candidate-needs-live-validation` means that the generated configuration now includes the Windows native surface. A read-only live CU check is still required before removing any compatibility measure.

`manage.ps1 install` installs the DLL, target-window guard, and CU proxy environment; `manage.ps1 uninstall` restores them using their ownership records and hashes. The script patches change only their entrypoints in the current runtime, never the helper executable. When a Codex update switches runtimes, the monitor asks for review instead of applying an old patch automatically. The proxy installer defaults to `http://127.0.0.1:7890` and records the selected value.

### Installation

Locate the `codex-computer-use.exe` used by your Computer Use runtime. Replace the placeholder path below with its actual path.

Run these commands from the `capture-compat` directory:

```powershell
$helperPath = 'C:\path\to\codex-computer-use.exe'

# Preview the installation target
.\install.ps1 -HelperPath $helperPath -WhatIf

# Exit the running helper before installing
.\install.ps1 -HelperPath $helperPath -Action Install
```

Restart Computer Use so that the helper loads the new DLL. Install beside the helper, rather than beside the main desktop application or in a Windows system directory.

The installer adds `version.dll` and `codex-capture-compat.install.json`. It does not modify the helper executable or stop running processes.

### Verify operation

Open `dist/capture_test_window.exe`, select that window through Computer Use, and take a screenshot. Check the image, then test repeated screenshots and window resizing. You can close the test window manually; it also exits automatically after ten minutes.

A passing probe confirms the tested compatibility paths. Operation through the official helper must also be verified. See the [validation and troubleshooting guide](capture-compat/docs/validation_en.md) for the full procedure.

### Upgrade and uninstall

To upgrade, build the new version and exit any helper using the installed DLL. Then run:

```powershell
.\install.ps1 -HelperPath $helperPath -Action Uninstall
.\install.ps1 -HelperPath $helperPath -Action Install
```

To remove the compatibility layer, run only the uninstall command and restart Computer Use. The script refuses to overwrite a different existing DLL. Removal checks the helper path and installed DLL hash against the installation record.

The helper directory may change after a Codex update. Check the actual path again before installing. See the [build and usage guide](capture-compat/README_en.md) for the complete installation rules.

## Implementation overview

```text
Computer Use helper
  └─ Local version.dll
      ├─ System version exports → Original DLL in System32
      └─ RoGetActivationFactory import hook
          └─ WGC frame pools and capture sessions
              ├─ Missing border property interface → Compatibility interface
              └─ Eligible frame events → MTA thread pool workers
```

`SetIsBorderRequired` is a WinRT/COM property operation, not a `version.dll` export. The DLL serves as the loading entry point and forwards system version exports. The capture compatibility logic hooks interface queries and event subscriptions on WGC objects.

The border fallback applies only when the native interface query returns `E_NOINTERFACE`. Asynchronous dispatch also requires a frame pool without a `DispatcherQueue` and a callback that supports invocation across threads. See the [implementation guide](capture-compat/docs/implementation_en.md) for event cancellation, object lifetime, and error handling details.

## Project structure

```text
capture-compat/
├─ README.md              Build and usage guide (Chinese)
├─ README_en.md           Build and usage guide (English)
├─ build.ps1              Builds the DLL and tools; runs unit tests
├─ install.ps1            Installation, removal, and file verification
├─ package.ps1            Release ZIP and SHA-256 checksum generation
├─ validate.ps1           Live Windows 10 regression tests
├─ src/                   DLL proxy, COM hooks, and callback dispatch
├─ tests/                 Unit tests, capture probe, and test window
├─ docs/                  Implementation, validation, and troubleshooting
├─ build/                 Intermediate build files (generated)
├─ dist/                  Deployable artifacts (generated)
└─ validation/            Test reports and captured images (generated)
```

The project's `.gitignore` excludes `build/`, `dist/`, and `validation/`. These directories may not exist in a fresh source checkout. Packages are written to `artifacts/` at the repository root, which is also excluded from version control.

## CI and releases

The [Build and release](https://github.com/MagicalAstrogy/CodexComputerUseFix/actions/workflows/build.yml) workflow builds and tests regular and Trace configurations on pushes to `main`, pull requests targeting `main`, and manual runs. Downloadable Actions artifacts are retained for 14 days.

Pushing a version tag such as `v1.0.0` creates a GitHub Release after both builds pass, with two ZIPs and their checksum files. Tags with a suffix such as `-rc.1` produce prereleases. CI covers COM, callback dispatch, installation, and packaging tests; real screenshots still require validation on a Windows 10 interactive desktop.

To publish, first push the workflow and desired source revision to `main`, then tag that commit and push the tag:

```powershell
# Example version; choose an unused tag for the release.
git tag -a v1.0.0 -m 'Release v1.0.0'
git push origin v1.0.0
```

Manual workflow runs only produce Actions artifacts. Publishing uses the built-in `GITHUB_TOKEN`; no personal access token is required. Existing releases are not overwritten. See the [CI and release guide](capture-compat/docs/ci_en.md) for local packaging and checksum verification.

## Scope and compatibility

- Only x64 builds are provided, targeting helpers that use Windows Graphics Capture.
- The helper must allow loading a local `version.dll` and directly import `RoGetActivationFactory` in its main EXE.
- Compatibility behavior is selected by actual interface support. It does not change the reported Windows version or capture permissions.
- Windows 11, other helper builds, and different graphics environments require separate validation. This layer does not address every possible screenshot failure.
- The DLL is unsigned. Asynchronous dispatch changes the callback thread and the timing of error returns; see the [implementation guide](capture-compat/docs/implementation_en.md) for the constraints.

## Documentation

Detailed guides are available in English and Simplified Chinese:

- [Build and usage](capture-compat/README_en.md)
- [Implementation](capture-compat/docs/implementation_en.md)
- [Validation and troubleshooting](capture-compat/docs/validation_en.md)
- [CI and releases](capture-compat/docs/ci_en.md)

## License

This project is licensed under [WTFPL v2](https://www.wtfpl.net/about/). See [LICENSE](LICENSE) for the full text.
