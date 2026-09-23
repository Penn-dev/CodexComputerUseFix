$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install.ps1'
$fixture = Join-Path $PSScriptRoot ('fixture-' + [Guid]::NewGuid().ToString('N'))
$launcherDirectory = Join-Path $fixture 'node_modules\@oai\cua-repl\bin'
$launcher = Join-Path $launcherDirectory 'cua-repl.mjs'

try {
    New-Item -ItemType Directory -Path $launcherDirectory -Force | Out-Null
    [IO.File]::WriteAllText($launcher, "#!/usr/bin/env node`nimport * as cua_repl from `"@oai/cua-repl`";`ntry {`n  await cua_repl.launch();`n} catch (error) {}`n", [Text.UTF8Encoding]::new($false))
    $originalHash = (Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash

    & $installer -LauncherPath $launcher -Action Install -ProxyUrl 'http://127.0.0.1:7890' | Out-Null
    $content = [IO.File]::ReadAllText($launcher)
    $proxyPosition = $content.IndexOf('http.setGlobalProxyFromEnv();')
    $importPosition = $content.IndexOf('await import("@oai/cua-repl")')
    if ($proxyPosition -lt 0 -or $importPosition -le $proxyPosition) { throw 'Proxy setup must precede CU module import.' }
    if ($content.Contains('import * as cua_repl')) { throw 'Static CU import remained.' }
    & node --check $launcher
    if ($LASTEXITCODE -ne 0) { throw 'Patched launcher failed node --check.' }
    & $installer -LauncherPath $launcher -Action Install | Out-Null
    & $installer -LauncherPath $launcher -Action Uninstall | Out-Null
    if ((Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash -ne $originalHash) { throw 'Uninstall did not restore exact original bytes.' }
    if ((Test-Path -LiteralPath "$launcher.codex-cu-proxy-env.install.json") -or (Test-Path -LiteralPath "$launcher.codex-cu-proxy-env.bak")) { throw 'Ownership files remained after uninstall.' }
    'PASS: proxy setup precedes dynamic import; install is idempotent; uninstall restores exact bytes.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
