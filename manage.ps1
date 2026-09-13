[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'install', 'uninstall', 'monitor-install', 'monitor-uninstall')]
    [string]$Action = 'status',
    [string]$HelperPath,
    [string]$RuntimeRoot = "$env:LOCALAPPDATA\OpenAI\Codex\runtimes\cua_node",
    [string]$PluginRoot = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\unified-computer-use",
    [string]$StatePath = "$env:LOCALAPPDATA\CodexComputerUseFix\monitor-state.json",
    [switch]$SkipIssueCheck,
    [switch]$Json,
    [switch]$NotifyOnChange,
    [switch]$Daily
)

$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'capture-compat\install.ps1'
$taskName = 'CodexComputerUseFix-Monitor'
$issueIds = @(42941, 43498, 43594)

function Get-LatestDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    Get-ChildItem -LiteralPath $Path -Directory |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-Helpers([string]$Root, [string]$ExplicitPath) {
    if ($ExplicitPath) {
        return ,(Get-Item -LiteralPath (Resolve-Path -LiteralPath $ExplicitPath).Path)
    }
    $runtime = Get-LatestDirectory $Root
    if (-not $runtime) { return @() }
    @(Get-ChildItem -LiteralPath $runtime.FullName -Recurse -Filter 'codex-computer-use.exe' -File |
        Where-Object { $_.FullName -match '\\node_modules\\@oai\\(cua|sky)\\bin\\windows\\codex-computer-use\.exe$' } |
        Sort-Object FullName)
}

function Get-InstallState([IO.FileInfo]$Helper) {
    $directory = $Helper.DirectoryName
    $dll = Join-Path $directory 'version.dll'
    $recordPath = Join-Path $directory 'codex-capture-compat.install.json'
    $record = $null
    if (Test-Path -LiteralPath $recordPath) {
        try { $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json } catch { $record = $null }
    }
    $dllHash = if (Test-Path -LiteralPath $dll) { (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash } else { $null }
    $owned = $false
    if ($record -and $dllHash) {
        $owned = [string]::Equals($record.helperPath, $Helper.FullName, [StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($record.dllSha256, $dllHash, [StringComparison]::OrdinalIgnoreCase)
    }
    [pscustomobject]@{
        helperPath = $Helper.FullName
        helperSha256 = (Get-FileHash -LiteralPath $Helper.FullName -Algorithm SHA256).Hash
        dllPresent = [bool]$dllHash
        installRecordPresent = [bool]$record
        ownedInstall = $owned
        dllSha256 = $dllHash
    }
}

function Get-RoutingState([string]$Root) {
    $plugin = Get-LatestDirectory $Root
    if (-not $plugin) {
        return [pscustomobject]@{ pluginVersion = $null; configPath = $null; surfaces = @(); skyRegistered = $false; state = 'plugin-missing' }
    }
    $configPath = Join-Path $plugin.FullName '.mcp.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return [pscustomobject]@{ pluginVersion = $plugin.Name; configPath = $configPath; surfaces = @(); skyRegistered = $false; state = 'config-missing' }
    }
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    $envConfig = $config.mcpServers.cua_repl.env
    $surfaces = @([string]$envConfig.CUA_REPL_ENABLED_SURFACES -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $services = $null
    try { $services = [string]$envConfig.NODE_REPL_TRUSTED_SERVICES | ConvertFrom-Json } catch { $services = $null }
    $hasComputer = $surfaces -contains 'computer'
    $hasSky = $null -ne $services -and $null -ne $services.sky
    $state = if ($hasComputer -and $hasSky) { 'official-path-candidate-needs-live-validation' } else { 'legacy-native-route-required' }
    [pscustomobject]@{
        pluginVersion = $plugin.Name
        configPath = $configPath
        surfaces = $surfaces
        skyRegistered = $hasSky
        state = $state
    }
}

function Get-IssueState([switch]$Skip) {
    if ($Skip) { return @() }
    $headers = @{ 'User-Agent' = 'CodexComputerUseFix'; 'Accept' = 'application/vnd.github+json' }
    @($issueIds | ForEach-Object {
        $id = $_
        try {
            $issue = Invoke-RestMethod -Uri "https://api.github.com/repos/openai/codex/issues/$id" -Headers $headers -TimeoutSec 10
            [pscustomobject]@{ id = $id; state = $issue.state; updatedAt = $issue.updated_at; url = $issue.html_url }
        } catch {
            [pscustomobject]@{ id = $id; state = 'unavailable'; updatedAt = $null; url = "https://github.com/openai/codex/issues/$id" }
        }
    })
}

function Get-CurrentState {
    $runtime = Get-LatestDirectory $RuntimeRoot
    $helpers = @(Get-Helpers $RuntimeRoot $HelperPath | ForEach-Object { Get-InstallState $_ })
    [pscustomobject]@{
        checkedAt = (Get-Date).ToString('o')
        osBuild = [Environment]::OSVersion.Version.Build
        runtimeId = if ($runtime) { $runtime.Name } else { $null }
        captureCompatibility = [pscustomobject]@{
            state = if ($helpers.Count -eq 0) { 'helper-missing' } elseif (@($helpers | Where-Object ownedInstall).Count -eq $helpers.Count) { 'installed-and-owned' } elseif (@($helpers | Where-Object dllPresent).Count -gt 0) { 'mixed-or-unowned' } else { 'not-installed-needs-validation' }
            helpers = $helpers
        }
        nativeRouting = Get-RoutingState $PluginRoot
        officialIssues = @(Get-IssueState -Skip:$SkipIssueCheck)
    }
}

function Get-StateSignature($State) {
    # Only a closed issue is actionable. Network failures and ordinary comments must not create reminders.
    $issues = @($State.officialIssues | Where-Object state -eq 'closed' | ForEach-Object { [string]$_.id }) -join ';'
    $helpers = @($State.captureCompatibility.helpers | ForEach-Object { "$($_.helperPath):$($_.helperSha256):$($_.ownedInstall)" }) -join ';'
    "$($State.runtimeId)|$($State.nativeRouting.pluginVersion)|$($State.nativeRouting.state)|$($State.nativeRouting.surfaces -join ',')|$helpers|$issues"
}

function Save-MonitorState($State) {
    $directory = Split-Path -Parent $StatePath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [pscustomobject]@{ signature = Get-StateSignature $State; state = $State } |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $StatePath -Encoding utf8
}

function Show-ChangeNotification([string]$Message) {
    $directory = Split-Path -Parent $StatePath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Add-Content -LiteralPath (Join-Path $directory 'monitor.log') -Encoding utf8 -Value "$(Get-Date -Format o) $Message"
    try { & msg.exe $env:USERNAME /TIME:120 $Message 2>$null } catch { Write-Warning $Message }
}

function Invoke-Status {
    if ($NotifyOnChange -and $Daily -and (Test-Path -LiteralPath $StatePath)) {
        try {
            $saved = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
            if (([datetime]$saved.state.checkedAt).ToLocalTime().Date -eq (Get-Date).Date) { return }
        } catch {
            # A corrupt or old state file should trigger a fresh check and be replaced below.
        }
    }
    $state = Get-CurrentState
    if ($NotifyOnChange) {
        $previous = $null
        if (Test-Path -LiteralPath $StatePath) {
            try { $previous = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json } catch { $previous = $null }
        }
        $signature = Get-StateSignature $state
        if ($previous -and $previous.signature -ne $signature) {
            Show-ChangeNotification 'Codex Computer Use 状态发生变化，请运行 manage.ps1 status 复核。'
        }
        Save-MonitorState $state
    }
    if ($Json) { $state | ConvertTo-Json -Depth 8; return }
    $state | Format-List checkedAt, osBuild, runtimeId
    $state.captureCompatibility | Format-List state
    $state.captureCompatibility.helpers | Format-Table helperPath, dllPresent, installRecordPresent, ownedInstall -AutoSize
    $state.nativeRouting | Format-List pluginVersion, configPath, surfaces, skyRegistered, state
    if ($state.officialIssues.Count -gt 0) { $state.officialIssues | Format-Table id, state, updatedAt, url -AutoSize }
}

function Invoke-InstallAction([string]$InstallAction) {
    $helpers = @(Get-Helpers $RuntimeRoot $HelperPath)
    if ($helpers.Count -eq 0) { throw 'No current codex-computer-use.exe helper was found.' }
    foreach ($helper in $helpers) { & $installer -HelperPath $helper.FullName -Action $InstallAction }
}

function Install-Monitor {
    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -File `"$PSCommandPath`" status -NotifyOnChange -Daily"
    $taskAction = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments
    $triggers = @(
        New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        New-ScheduledTaskTrigger -Daily -At '10:00'
    )
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $triggers -Principal $principal -Settings $settings -Description 'Checks Codex Computer Use runtime, local compatibility patch and related official issues after sign-in and daily.' -Force | Out-Null
    Save-MonitorState (Get-CurrentState)
    Write-Output "Installed scheduled task: $taskName"
}

function Uninstall-Monitor {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
    Write-Output "Removed scheduled task: $taskName"
}

switch ($Action) {
    'status' { Invoke-Status }
    'install' { Invoke-InstallAction 'Install' }
    'uninstall' { Invoke-InstallAction 'Uninstall' }
    'monitor-install' { Install-Monitor }
    'monitor-uninstall' { Uninstall-Monitor }
}
