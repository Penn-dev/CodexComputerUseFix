# Codex Capture Compat

[简体中文](README.md) | [English](README_en.md)

Repairs confirmed Codex Computer Use defects on Windows 10: native capture, existing proxy inheritance, native release, and notifications triggered by actual capture failures. See the [maintenance audit](docs/cu-maintenance-audit.md) for evidence and current acceptance results.

## Components

- `capture-compat/`: a local `version.dll` beside the actual helper. It handles the optional border interface and capture callback blocking, preserving the default border and official helper.
- `browser-proxy/`: fixed system configuration starts the current official runtime and forwards existing proxy settings and MCP bytes.
- `windows-lifecycle/`: exposes this repair's `sky.end_turn()` and closes this client's native connection after normal cleanup or physical Escape.
- `capture-notify/`: handles actual native capture results and requests a Windows popup after repeated confirmed failures.
- `native-runtime/`: loads the last two components through official `NODE_REPL_WORKER_WRAPPER` and in-memory Node hooks. Official sandbox commands, arguments, working directory and stdio remain intact.

Fixed modules live in `%USERPROFILE%\.codex\plugins\cu-compat`. Wrapper parents wait for their CU workers. There is no scheduled task, log polling or independent background monitor. The former proxy injection, automatic window guard and `CodexComputerUseFix-Monitor` are retired.

## Manage capture DLL

```powershell
.\manage.ps1 status -Json
.\manage.ps1 install
.\manage.ps1 uninstall
```

Selection follows the configured plugin launch path. Use the actual `-HelperPath` when several candidates exist. Verify capture with official CU before installing a DLL into a new runtime. Ownership checks do not replace a capture result. Browser control does not use this DLL.

Original reported defects: [border interface #25178](https://github.com/openai/codex/issues/25178), [capture callback #35446](https://github.com/openai/codex/issues/35446).

## Install the separate runtime repairs

Use existing PowerShell 7 and Node.js:

```powershell
.\browser-proxy\persistent.ps1
.\native-runtime\install.ps1
```

For an existing owned proxy entry, `browser-proxy/persistent.ps1 -Action Update` updates its script and keeps a matching rollback copy. The launcher reads the current desktop-generated manifest at startup. It forwards existing `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY` and enables Node environment proxy support. It preserves the official runtime and protocol.

Native cleanup sends the existing helper `end_turn`, then disconnects only this client. A new turn creates a fresh client. Physical Escape cleanup closes the current connection without issuing another helper control request. Other clients retain their connections.

Fully exit and reopen Codex after installation. In official `node_repl`:

```javascript
var { sky } = await import('@oai/sky');
await sky.compat_status();
// captureReminder: 'on-result', polling: false, nativeReleaseAvailable: true
// After the last native UI action:
await sky.end_turn();
```

The legacy `windows-lifecycle/install.ps1 -Action Uninstall -ClientPath <original client path>` restores only a recorded source patch. New installations use the fixed loader.

Uninstall the loader before the proxy launcher:

```powershell
.\native-runtime\install.ps1 -Action Uninstall
.\browser-proxy\persistent.ps1 -Action Uninstall
```

Installers record ownership and preserve unrelated settings.

## Notifications

Two native capture failures of the same known class within ten minutes in one session trigger a popup. Known classes are border-interface failure, `FrameArrived timed out`, and `window capture timed out`. Successful captures and unrelated errors reset the sequence. Duplicate alerts are suppressed until recovery. State remains in memory; no screenshots or page content are stored.

The sandboxed worker emits a tagged stderr event. Its existing wrapper forwards the original bytes and calls Windows `msg.exe` on the interactive desktop; the popup expires after two minutes. Unavailable event bridges report through the tool result; desktop send errors appear in runtime diagnostics. No new listening port or notification file is used. Runtime versions, paths, hashes, missing DLLs, browser network failures and issue changes do not trigger capture alerts.

## Build and verify

```powershell
.\capture-compat\build.ps1
.\capture-compat\tests\install_tests.ps1
.\capture-compat\tests\manage_tests.ps1
node --test windows-lifecycle/tests.mjs capture-notify/tests.mjs native-runtime/tests.mjs
.\native-runtime\install-tests.ps1
.\browser-proxy\persistent-tests.ps1 -NodePath (Get-Command node.exe).Source
.\capture-compat\validate.ps1
```

MSVC, MASM and Windows SDK are required for DLL builds. Set `CU_TEST_MODULES` to the actual runtime's `bin/node_modules` to test the current official client with the in-memory loader. Desktop acceptance covers actual capture, normal release, physical Escape and visible notifications.

Also set `CU_TEST_CLI` to the current Codex CLI executable to validate the installed repair through the official supervisor with the desktop's narrowed plugin trust roots.

- [Build and usage](capture-compat/README_en.md)
- [Windows native usage](docs/windows-computer-use.md)
- [Implementation](capture-compat/docs/implementation_en.md)
- [Validation](capture-compat/docs/validation_en.md)
- [CI and release](capture-compat/docs/ci_en.md)
- [License](LICENSE)
