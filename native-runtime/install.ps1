[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Install','Uninstall')][string]$Action = 'Install',
    [string]$ConfigPath = "$env:ProgramData\OpenAI\Codex\config.toml",
    [string]$Destination = "$env:USERPROFILE\.codex\plugins\cu-compat",
    [string]$NodePath = (Get-Command node.exe -ErrorAction Stop).Source
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$config = [IO.Path]::GetFullPath($ConfigPath)
$destinationRoot = [IO.Path]::GetFullPath($Destination)
$recordPath = "$config.codex-cu-native.json"
$source = [IO.File]::ReadAllText($config)
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
if (Test-Path -LiteralPath $recordPath) {
    $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    if ($record.config -ne $config -or $record.destination -ne $destinationRoot) { throw 'Native loader record target mismatch.' }
    foreach ($block in @($record.transportBlock,$record.envBlock)) {
        if ([regex]::Matches($source,[regex]::Escape($block)).Count -ne 1) { throw 'Owned native configuration changed.' }
    }
    foreach ($file in $record.files) {
        if ((Hash $file.target) -ne $file.hash) { throw 'Owned native loader file changed.' }
    }
    if ($Action -eq 'Install') {
        foreach ($file in $record.files) {
            $relative = [IO.Path]::GetRelativePath($destinationRoot, $file.target)
            if ((Hash (Join-Path $root $relative)) -ne $file.hash) { throw 'Native loader source changed. Uninstall the owned loader, then install this version.' }
        }
        Write-Output 'Fixed native loader already installed.'; return
    }
    if ($PSCmdlet.ShouldProcess($config,'Remove the owned native loader configuration and files')) {
        [IO.File]::WriteAllText($config,$source.Replace($record.transportBlock,'').Replace($record.envBlock,''),[Text.UTF8Encoding]::new($false))
        foreach ($file in $record.files) { Remove-Item -LiteralPath $file.target }
        Remove-Item -LiteralPath $recordPath
    }
    return
}
if ($Action -eq 'Uninstall') { throw 'Native loader ownership record missing.' }
if ($source -match '(?m)^\s*\[mcp_servers\.node_repl\]\s*$' -or $source.Contains('NODE_REPL_WORKER_WRAPPER')) { throw 'An unowned native transport or worker wrapper is already configured.' }
$envHeader='[mcp_servers.node_repl.env]'
if ([regex]::Matches($source,[regex]::Escape($envHeader)).Count -ne 1) { throw 'Expected one existing native environment section.' }
$launcher=Join-Path (Split-Path -Parent $config) 'codex-cu-browser-proxy-launch.ps1'
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Install the persistent CU launcher first.' }
$shell=(Get-Process -Id $PID).Path
$wrapper=Join-Path $destinationRoot 'native-runtime\worker-wrapper.cjs'
$commandJson=ConvertTo-Json -InputObject @($NodePath,$wrapper) -Compress
foreach ($value in @($shell,$launcher,$commandJson)) { if ($value.Contains("'")) { throw 'Single quotes in configured paths are unsupported.' } }
$transportBlock=@"
# BEGIN codex-cu-native-transport:v1
[mcp_servers.node_repl]
command = '$shell'
args = ['-NoProfile', '-NonInteractive', '-File', '$launcher', '-Native']
startup_timeout_sec = 120
# END codex-cu-native-transport:v1

"@
$envBlock=@"

# BEGIN codex-cu-native-loader:v1
NODE_REPL_WORKER_WRAPPER = '$commandJson'
# END codex-cu-native-loader:v1
"@
$files=@('native-runtime/worker-wrapper.cjs','native-runtime/bootstrap.mjs','windows-lifecycle/lifecycle.mjs','capture-notify/health.mjs','capture-notify/notify.mjs')
foreach ($relative in $files) { if (Test-Path -LiteralPath (Join-Path $destinationRoot $relative)) { throw 'An unowned native loader file already exists.' } }
if ($PSCmdlet.ShouldProcess($config,'Load CU cleanup and observed-failure notifications from a fixed directory')) {
    $created=@()
    try {
        foreach ($relative in $files) {
            $target=Join-Path $destinationRoot $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $target
            $created += [pscustomobject]@{target=$target;hash=(Hash $target)}
        }
        Copy-Item -LiteralPath $config -Destination "$config.before-cu-native" -Force
        $updated=$source.Replace($envHeader,$transportBlock+$envHeader+$envBlock)
        [IO.File]::WriteAllText($config,$updated,[Text.UTF8Encoding]::new($false))
        $record=[pscustomobject]@{config=$config;destination=$destinationRoot;transportBlock=$transportBlock;envBlock=$envBlock;files=$created;installedAt=[DateTimeOffset]::Now.ToString('o')}
        [IO.File]::WriteAllText($recordPath,($record|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    } catch {
        [IO.File]::WriteAllText($config,$source,[Text.UTF8Encoding]::new($false))
        foreach ($file in $created) { Remove-Item -LiteralPath $file.target }
        throw
    }
    Write-Output 'Fixed native loader installed. Reload Codex to adopt the startup environment.'
}
