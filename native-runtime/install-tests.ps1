$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path $root ('capture-compat\validation\native-install-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    $config=Join-Path $fixture 'config.toml'
    $original="[mcp_servers.node_repl.env]`nHTTP_PROXY = 'http://existing:7890'`n`n[other]`nkeep = true`n"
    [IO.File]::WriteAllText($config,$original)
    Copy-Item -LiteralPath (Join-Path $root 'browser-proxy\launch.ps1') -Destination (Join-Path $fixture 'codex-cu-browser-proxy-launch.ps1')
    $parameters=@{ConfigPath=$config;Destination=(Join-Path $fixture 'fixed files');NodePath=(Get-Command node.exe).Source}
    & (Join-Path $PSScriptRoot 'install.ps1') @parameters | Out-Null
    & (Join-Path $PSScriptRoot 'install.ps1') @parameters | Out-Null
    $updated=[IO.File]::ReadAllText($config)
    if ($updated -notmatch 'NODE_REPL_WORKER_WRAPPER' -or $updated -notmatch '\[mcp_servers.node_repl\]' -or $updated -notmatch 'keep = true') {throw 'Native configuration did not preserve existing settings.'}
    $changedFile=Join-Path $parameters.Destination 'native-runtime\worker-wrapper.cjs'
    $bytes=[IO.File]::ReadAllBytes($changedFile)
    Add-Content -LiteralPath $changedFile -Value 'changed'
    $refused=$false;try{& (Join-Path $PSScriptRoot 'install.ps1') @parameters -Action Uninstall | Out-Null}catch{$refused=$true}
    if(-not $refused){throw 'Uninstall overwrote a changed loader.'}
    [IO.File]::WriteAllBytes($changedFile,$bytes)
    Add-Content -LiteralPath $config -Value "`n[user-added]`nkeep2 = true"
    & (Join-Path $PSScriptRoot 'install.ps1') @parameters -Action Uninstall | Out-Null
    $restored=[IO.File]::ReadAllText($config)
    if(-not $restored.StartsWith($original) -or $restored -notmatch 'keep2 = true'){throw 'Uninstall did not preserve original and later settings.'}
    'PASS: native loader install, idempotence, ownership, and preservation of later configuration.'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $prefix=[IO.Path]::GetFullPath((Join-Path $root 'capture-compat\validation'))+'\'
    if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
