$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install.ps1'
$fixture = Join-Path $PSScriptRoot ('fixture-' + [Guid]::NewGuid().ToString('N'))
$launcherDirectory = Join-Path $fixture 'node_modules\@oai\cua-repl\bin'
$launcher = Join-Path $launcherDirectory 'cua-repl.mjs'

try {
    New-Item -ItemType Directory -Path $launcherDirectory -Force | Out-Null
    [IO.File]::WriteAllText($launcher, "#!/usr/bin/env node`ntry {`n  process.stdout.write('fixture');`n} catch (error) {}`n", [Text.UTF8Encoding]::new($false))
    $originalHash = (Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash

    & $installer -LauncherPath $launcher -Action Install -ProxyUrl 'http://127.0.0.1:7890' | Out-Null
    $text = [IO.File]::ReadAllText($launcher)
    if (-not $text.Contains('codex-cu-proxy-env:v1')) { throw 'Install marker missing.' }
    if (-not $text.Contains('NODE_USE_ENV_PROXY: "1"')) { throw 'Node proxy opt-in missing.' }
    if (-not $text.Contains('HTTP_PROXY: "http://127.0.0.1:7890"')) { throw 'Proxy URL missing.' }
    $recordPath = "$launcher.codex-cu-proxy-env.install.json"
    $backupPath = "$launcher.codex-cu-proxy-env.bak"
    if (-not (Test-Path -LiteralPath $recordPath) -or -not (Test-Path -LiteralPath $backupPath)) { throw 'Ownership files missing.' }

    & $installer -LauncherPath $launcher -Action Install | Out-Null
    & $installer -LauncherPath $launcher -Action Uninstall | Out-Null
    if ((Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash -ne $originalHash) { throw 'Uninstall did not restore the exact original.' }
    if ((Test-Path -LiteralPath $recordPath) -or (Test-Path -LiteralPath $backupPath)) { throw 'Ownership files remained after uninstall.' }

    'PASS: proxy environment install is idempotent and uninstall restores exact bytes.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
