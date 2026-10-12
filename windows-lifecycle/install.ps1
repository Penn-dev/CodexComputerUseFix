[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ClientPath,
    [ValidateSet('Uninstall')][string]$Action = 'Uninstall'
)
$ErrorActionPreference = 'Stop'
$target = (Resolve-Path -LiteralPath $ClientPath).Path
if ([IO.Path]::GetFileName($target) -ne 'computer_use_client_base.js') { throw 'Specify the actual Windows client base source.' }
$module = Join-Path (Split-Path -Parent $target) 'codex_windows_lifecycle.mjs'
$recordPath = "$target.codex-cu-lifecycle.json"
$backup = "$target.codex-cu-lifecycle.bak"
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

if ($Action -eq 'Uninstall') {
    if (-not (Test-Path -LiteralPath $recordPath)) { throw 'Lifecycle ownership record missing.' }
    $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json
    if ($record.target -ne $target -or (Hash $target) -ne $record.patchedHash -or (Hash $backup) -ne $record.originalHash -or (Hash $module) -ne $record.moduleHash) { throw 'Lifecycle files changed; refusing to overwrite them.' }
    if ($PSCmdlet.ShouldProcess($target,'Restore the recorded Windows lifecycle source')) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Remove-Item -LiteralPath $module,$recordPath,$backup
        Write-Output 'Windows lifecycle patch removed. Reload the CU service.'
    }
    return
}
