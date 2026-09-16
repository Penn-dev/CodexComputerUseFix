[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$SkyPath,
    [ValidateSet('Install','Uninstall')][string]$Action = 'Install'
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SkyPath).Path
if ([IO.Path]::GetFileName($source) -ine 'sky.js') {
    throw 'SkyPath must point to the @oai/sky sky.js entrypoint.'
}

$marker = 'codex-cu-target-window-guard:v1'
$backup = "$source.codex-cu-target-window-guard.bak"
$recordPath = "$source.codex-cu-target-window-guard.install.json"
$needle = 'const e=(...e)=>c({type:"execute",method:t,args:e});Reflect.set(i,t,e)'
$replacement = 'const e=(...e)=>"get_window_state"===t&&e[0]&&e[0].window?c({type:"execute",method:"activate_window",args:[{window:e[0].window}]}).then(()=>c({type:"execute",method:"get_window",args:[{id:e[0].window.id,app:e[0].window.app}]})).then(r=>c({type:"execute",method:t,args:[{...e[0],window:r},...e.slice(1)]})):c({type:"execute",method:t,args:e});/* codex-cu-target-window-guard:v1 */Reflect.set(i,t,e)'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

if ($Action -eq 'Install') {
    $text = [IO.File]::ReadAllText($source)
    if ($text.Contains($marker)) {
        if (-not (Test-Path -LiteralPath $recordPath)) {
            throw 'The target guard marker exists without an install record; refusing to claim ownership.'
        }
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        if ((Get-Hash $source) -ne $record.patchedSha256) {
            throw 'The guarded sky.js changed after installation.'
        }
        Write-Output 'The target-window guard is already installed.'
        return
    }
    if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $recordPath)) {
        throw 'A previous target-window guard backup or record exists; inspect it before installing.'
    }
    $matches = ([regex]::Matches($text, [regex]::Escape($needle))).Count
    if ($matches -ne 1) {
        throw "Unsupported @oai/sky build: expected one patch point, found $matches."
    }
    if ($PSCmdlet.ShouldProcess($source, 'Install target-window activation guard')) {
        Copy-Item -LiteralPath $source -Destination $backup
        $originalHash = Get-Hash $backup
        [IO.File]::WriteAllText($source, $text.Replace($needle, $replacement), $utf8)
        $patchedHash = Get-Hash $source
        if ($patchedHash -eq $originalHash -or -not ([IO.File]::ReadAllText($source).Contains($marker))) {
            Copy-Item -LiteralPath $backup -Destination $source -Force
            Remove-Item -LiteralPath $backup -Force
            throw 'Target-window guard verification failed; the original file was restored.'
        }
        [pscustomobject]@{
            sourcePath = $source
            originalSha256 = $originalHash
            patchedSha256 = $patchedHash
            marker = $marker
            installedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $recordPath -Encoding utf8
        Write-Output "Installed target-window guard: $source"
        Write-Output 'Restart the Node REPL / Codex before validating Computer Use.'
    }
    return
}

if (-not (Test-Path -LiteralPath $recordPath)) {
    if (-not (Test-Path -LiteralPath $backup) -and -not ([IO.File]::ReadAllText($source).Contains($marker))) {
        Write-Output 'The target-window guard is not installed.'
        return
    }
    throw 'Target-window guard install record missing; refusing to restore an unowned file.'
}
if (-not (Test-Path -LiteralPath $backup)) {
    throw 'Target-window guard backup missing; refusing to modify sky.js.'
}
$record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
if (-not [string]::Equals($record.sourcePath, $source, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Target-window guard install record belongs to another sky.js path.'
}
if ((Get-Hash $source) -ne $record.patchedSha256) {
    throw 'sky.js changed since target-window guard installation; refusing to overwrite it.'
}
if ((Get-Hash $backup) -ne $record.originalSha256) {
    throw 'Target-window guard backup hash mismatch; refusing to restore it.'
}
if ($PSCmdlet.ShouldProcess($source, 'Uninstall target-window activation guard')) {
    Copy-Item -LiteralPath $backup -Destination $source -Force
    if ((Get-Hash $source) -ne $record.originalSha256) {
        throw 'Restored sky.js hash does not match the recorded original.'
    }
    Remove-Item -LiteralPath $backup -Force
    Remove-Item -LiteralPath $recordPath -Force
    Write-Output "Removed target-window guard: $source"
    Write-Output 'Restart the Node REPL / Codex before using Computer Use.'
}
