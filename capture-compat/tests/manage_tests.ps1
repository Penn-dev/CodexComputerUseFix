$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manager = Join-Path $project 'manage.ps1'
$fixture = Join-Path $PSScriptRoot ('..\validation\manage-fixture-' + [Guid]::NewGuid().ToString('N'))
$runtimeRoot = Join-Path $fixture 'runtimes'
$pluginRoot = Join-Path $fixture 'plugins'
$statePath = Join-Path $fixture 'state\monitor-state.json'
$runtime = Join-Path $runtimeRoot 'runtime-new'
$helperDirectory = Join-Path $runtime 'bin\node_modules\@oai\sky\bin\windows'
$skyDirectory = Join-Path $runtime 'bin\node_modules\@oai\sky\dist\project\cua\sky_js\src'
$skyPath = Join-Path $skyDirectory 'sky.js'
$plugin = Join-Path $pluginRoot '26.test'

try {
    New-Item -ItemType Directory -Path $helperDirectory, $skyDirectory, $plugin -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $helperDirectory 'codex-computer-use.exe') -Value 'fixture helper'
    Set-Content -LiteralPath $skyPath -Value 'fixture sky entrypoint'
    @{
        mcpServers = @{
            cua_repl = @{
                env = @{
                    CUA_REPL_ENABLED_SURFACES = 'browser'
                    NODE_REPL_TRUSTED_SERVICES = '{"browser":"@oai/browser-desktop/service"}'
                }
            }
        }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $plugin '.mcp.json') -Encoding utf8

    $state = & $manager status -RuntimeRoot $runtimeRoot -PluginRoot $pluginRoot -StatePath $statePath -SkipIssueCheck -Json | ConvertFrom-Json
    if ($state.runtimeId -ne 'runtime-new') { throw 'Latest runtime detection failed.' }
    if ($state.captureCompatibility.state -ne 'not-installed-needs-validation') { throw 'Unpatched helper state was classified incorrectly.' }
    if ($state.targetWindowGuard.state -ne 'not-installed') { throw 'Unpatched target-window guard state was classified incorrectly.' }
    if ($state.nativeRouting.state -ne 'legacy-native-route-required') { throw 'Browser-only routing was classified incorrectly.' }

    $config = Get-Content -Raw -LiteralPath (Join-Path $plugin '.mcp.json') | ConvertFrom-Json
    $config.mcpServers.cua_repl.env.CUA_REPL_ENABLED_SURFACES = 'browser,computer'
    $config.mcpServers.cua_repl.env.NODE_REPL_TRUSTED_SERVICES = '{"browser":"@oai/browser-desktop/service","sky":"@oai/sky/service"}'
    $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $plugin '.mcp.json') -Encoding utf8
    $state = & $manager status -RuntimeRoot $runtimeRoot -PluginRoot $pluginRoot -StatePath $statePath -SkipIssueCheck -Json | ConvertFrom-Json
    if ($state.nativeRouting.state -ne 'official-path-candidate-needs-live-validation') { throw 'Official-path candidate was classified incorrectly.' }

    & $manager status -RuntimeRoot $runtimeRoot -PluginRoot $pluginRoot -StatePath $statePath -SkipIssueCheck -NotifyOnChange -Json | Out-Null
    if (-not (Test-Path -LiteralPath $statePath)) { throw 'Monitor baseline was not written.' }
    'PASS: runtime discovery, capture patch state, target guard state, routing state and monitor baseline.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
