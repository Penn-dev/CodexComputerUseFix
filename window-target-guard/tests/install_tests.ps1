$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '..\install.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) "codex-cu-target-guard-$([guid]::NewGuid().ToString('N'))"
$sky = Join-Path $root 'sky.js'
$needle = 'const e=(...e)=>c({type:"execute",method:t,args:e});Reflect.set(i,t,e)'

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [IO.File]::WriteAllText($sky, "prefix;$needle;suffix", [Text.UTF8Encoding]::new($false))
    $originalHash = (Get-FileHash -LiteralPath $sky -Algorithm SHA256).Hash

    & $installer -SkyPath $sky -Action Install | Out-Null
    $patched = [IO.File]::ReadAllText($sky)
    if (-not $patched.Contains('codex-cu-target-window-guard:v1')) { throw 'Install did not add the guard marker.' }
    if (-not $patched.Contains('method:"activate_window"')) { throw 'Install did not add activation.' }
    if (-not $patched.Contains('method:"get_window"')) { throw 'Install did not add window rehydration.' }

    & $installer -SkyPath $sky -Action Install | Out-Null
    & $installer -SkyPath $sky -Action Uninstall | Out-Null
    if ((Get-FileHash -LiteralPath $sky -Algorithm SHA256).Hash -ne $originalHash) { throw 'Uninstall did not restore the original sky.js.' }
    if ((Test-Path "$sky.codex-cu-target-window-guard.bak") -or (Test-Path "$sky.codex-cu-target-window-guard.install.json")) {
        throw 'Uninstall left guard ownership files behind.'
    }
    & $installer -SkyPath $sky -Action Uninstall | Out-Null

    [IO.File]::WriteAllText($sky, 'unsupported-source', [Text.UTF8Encoding]::new($false))
    $failed = $false
    try { & $installer -SkyPath $sky -Action Install | Out-Null } catch { $failed = $_.Exception.Message -like 'Unsupported @oai/sky build:*' }
    if (-not $failed) { throw 'Unsupported source did not fail closed.' }

    Write-Output 'Target-window guard install tests passed.'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
