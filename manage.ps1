[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'install', 'uninstall')]
    [string]$Action = 'status',
    [string]$HelperPath,
    [string]$RuntimeRoot = "$env:LOCALAPPDATA\OpenAI\Codex\runtimes\cua_node",
    [string]$PluginRoot = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\unified-computer-use",
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'capture-compat\install.ps1'

function Get-RuntimeSelection {
    if ($HelperPath) {
        $helper = Get-Item -LiteralPath (Resolve-Path -LiteralPath $HelperPath).Path
        if ($helper.Name -ine 'codex-computer-use.exe') { throw 'HelperPath must identify codex-computer-use.exe.' }
        return [pscustomobject]@{ source = 'explicit-helper'; runtimeId = $null; root = $null; helpers = @($helper); candidates = @() }
    }
    $candidates = @()
    if (Test-Path -LiteralPath $PluginRoot) {
        $rootPrefix = [IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\', '/') + '\'
        foreach ($manifest in Get-ChildItem -LiteralPath $PluginRoot -Filter .mcp.json -File -Recurse) {
            try { $config = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json } catch { continue }
            foreach ($server in $config.mcpServers.psobject.Properties) {
                foreach ($entry in @($server.Value.command) + @($server.Value.args)) {
                    if (-not $entry -or -not [IO.Path]::IsPathRooted([string]$entry)) { continue }
                    $path = [IO.Path]::GetFullPath([string]$entry)
                    if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                        -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
                    $relative = $path.Substring($rootPrefix.Length)
                    $runtimeId = $relative.Split('\')[0]
                    if ($relative -notmatch '^[^\\]+\\bin\\') { continue }
                    $candidates += Join-Path $RuntimeRoot $runtimeId
                }
            }
        }
    }
    $candidates = @($candidates | Sort-Object -Unique)
    if ($candidates.Count -ne 1) {
        return [pscustomobject]@{ source = 'selection-required'; runtimeId = $null; root = $null; helpers = @(); candidates = $candidates }
    }
    $runtime = Get-Item -LiteralPath $candidates[0]
    $helpers = @('sky', 'cua' | ForEach-Object {
        $path = Join-Path $runtime.FullName "bin\node_modules\@oai\$_\bin\windows\codex-computer-use.exe"
        if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path }
    })
    [pscustomobject]@{ source = 'plugin-command'; runtimeId = $runtime.Name; root = $runtime.FullName; helpers = $helpers; candidates = $candidates }
}

function Get-InstallState([IO.FileInfo]$Helper) {
    $dll = Join-Path $Helper.DirectoryName 'version.dll'
    $recordPath = Join-Path $Helper.DirectoryName 'codex-capture-compat.install.json'
    $record = $null
    if (Test-Path -LiteralPath $recordPath) {
        try { $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json } catch { }
    }
    $helperHash = (Get-FileHash -LiteralPath $Helper.FullName -Algorithm SHA256).Hash
    $dllHash = if (Test-Path -LiteralPath $dll) { (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash } else { $null }
    $owned = $record -and $dllHash -and
        [string]::Equals($record.helperPath, $Helper.FullName, [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($record.dllSha256, $dllHash, [StringComparison]::OrdinalIgnoreCase)
    $state = if ($owned -and $record.helperSha256 -eq $helperHash) { 'installed-and-owned' }
        elseif ($owned) { 'helper-changed-needs-validation' }
        elseif ($dllHash -or $record) { 'mixed-or-unowned' }
        else { 'not-installed-needs-validation' }
    [pscustomobject]@{ helperPath = $Helper.FullName; helperSha256 = $helperHash; dllSha256 = $dllHash; state = $state }
}

function Get-CurrentState {
    $selection = Get-RuntimeSelection
    [pscustomobject]@{
        checkedAt = (Get-Date).ToString('o')
        osBuild = [Environment]::OSVersion.Version.Build
        runtimeId = $selection.runtimeId
        runtimeSelection = $selection.source
        runtimeCandidates = $selection.candidates
        captureCompatibility = @( $selection.helpers | ForEach-Object { Get-InstallState $_ } )
    }
}

function Invoke-InstallAction([string]$InstallAction) {
    $selection = Get-RuntimeSelection
    if ($selection.helpers.Count -eq 0) { throw 'No unambiguous configured helper was found. Specify the actual HelperPath.' }
    foreach ($helper in $selection.helpers) {
        & $installer -HelperPath $helper.FullName -Action $InstallAction
    }
}

switch ($Action) {
    'status' {
        $state = Get-CurrentState
        if ($Json) { $state | ConvertTo-Json -Depth 8 } else {
            $state | Format-List checkedAt, osBuild, runtimeId, runtimeSelection, runtimeCandidates
            $state.captureCompatibility | Format-Table -AutoSize
        }
    }
    'install' { Invoke-InstallAction 'Install' }
    'uninstall' { Invoke-InstallAction 'Uninstall' }
}
