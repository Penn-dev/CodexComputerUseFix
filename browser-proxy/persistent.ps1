[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Install','Update','Uninstall')][string]$Action = 'Install',
    [string]$ConfigPath = "$env:ProgramData\OpenAI\Codex\config.toml"
)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($ConfigPath)
$recordPath = "$target.codex-cu-browser-proxy.json"
$launcher = Join-Path (Split-Path -Parent $target) 'codex-cu-browser-proxy-launch.ps1'
$launcherSource = Join-Path $PSScriptRoot 'launch.ps1'
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
$start = '# BEGIN codex-cu-browser-proxy:v1'
$end = '# END codex-cu-browser-proxy:v1'
$source = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target) } else { '' }

if (Test-Path -LiteralPath $recordPath) {
    $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    if ($record.target -ne $target -or $record.launcher -ne $launcher -or
        (Hash $launcher) -ne $record.launcherHash -or
        ([regex]::Matches($source,[regex]::Escape($record.block))).Count -ne 1) {
        throw 'Owned proxy configuration changed; inspect before replacing it.'
    }
    if ($Action -eq 'Update') {
        if ($PSCmdlet.ShouldProcess($launcher, 'Update the recorded launcher and retain its matching rollback copy')) {
            Copy-Item -LiteralPath $launcher -Destination "$launcher.previous" -Force
            Copy-Item -LiteralPath $recordPath -Destination "$recordPath.previous" -Force
            try {
                Copy-Item -LiteralPath $launcherSource -Destination $launcher -Force
                $record.launcherHash = Hash $launcher
                [IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
            } catch {
                Copy-Item -LiteralPath "$launcher.previous" -Destination $launcher -Force
                Copy-Item -LiteralPath "$recordPath.previous" -Destination $recordPath -Force
                throw
            }
        }
        return
    }
    if ($Action -eq 'Install') {
        if ((Hash $launcherSource) -ne $record.launcherHash) { throw 'Proxy launcher source changed.' }
        Write-Output 'Persistent CUA proxy configuration already installed.'
        return
    }
    if ($PSCmdlet.ShouldProcess($target, 'Remove only the owned persistent CUA entry')) {
        $restored = $source.Replace($record.block, '')
        if (-not $record.existedBefore -and [string]::IsNullOrWhiteSpace($restored)) {
            Remove-Item -LiteralPath $target
        } else {
            [IO.File]::WriteAllText($target,$restored,[Text.UTF8Encoding]::new($false))
        }
        Remove-Item -LiteralPath $launcher,$recordPath
        Write-Output 'Persistent CUA entry removed. Reload the CU service.'
    }
    return
}
if ($Action -eq 'Uninstall') { throw 'Persistent proxy ownership record missing.' }
if (Test-Path -LiteralPath $launcher) { throw 'Unowned persistent launcher already exists.' }
if ($source.Contains($start) -or $source.Contains($end) -or $source -match '(?m)^\s*\[mcp_servers\.(?:cua_repl|"cua_repl"|''cua_repl'')(?:\.|\])') {
    throw 'Existing CUA configuration is not owned by this installer.'
}
$shellPath = (Get-Process -Id $PID).Path
if ([IO.Path]::GetFileName($shellPath) -ine 'pwsh.exe') { throw 'Run this installer in PowerShell 7.' }
if ($shellPath.Contains("'") -or $launcher.Contains("'")) { throw 'Unsupported quote in launcher path.' }
$block = @"

$start
[mcp_servers.cua_repl]
command = '$shellPath'
args = ['-NoProfile', '-NonInteractive', '-File', '$launcher']
env_vars = ['CODEX_WINDOWS_REGISTERED_CORE', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY']
startup_timeout_sec = 120
enabled_tools = ['js', 'js_reset', 'turn_ended']
omit_tools_from = ['code_mode', 'deferred']
$end

"@
if ($PSCmdlet.ShouldProcess($target,'Use the current official CUA runtime through a persistent proxy launcher')) {
    $existed = Test-Path -LiteralPath $target
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    try {
        Copy-Item -LiteralPath $launcherSource -Destination $launcher
        [IO.File]::WriteAllText($target,$source+$block,[Text.UTF8Encoding]::new($false))
        $record = [pscustomobject]@{target=$target;launcher=$launcher;launcherHash=(Hash $launcher);existedBefore=$existed;block=$block;installedAt=[DateTimeOffset]::Now.ToString('o')}
        [IO.File]::WriteAllText($recordPath,($record | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    } catch {
        if ($existed) { [IO.File]::WriteAllText($target,$source,[Text.UTF8Encoding]::new($false)) }
        elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target }
        Remove-Item -LiteralPath $launcher,$recordPath -ErrorAction SilentlyContinue
        throw
    }
    Write-Output 'Persistent CUA entry installed. Reload the CU service and verify browser operations.'
}
