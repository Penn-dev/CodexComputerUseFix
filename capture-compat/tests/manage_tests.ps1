$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manager = Join-Path $project 'manage.ps1'
$fixture = Join-Path (Join-Path $project 'capture-compat\validation') ('manage-fixture-' + [Guid]::NewGuid().ToString('N'))
$runtimeRoot = Join-Path $fixture 'runtimes'
$pluginRoot = Join-Path $fixture 'plugins'
$runtime = Join-Path $runtimeRoot 'configured'
$helperDirectory = Join-Path $runtime 'bin\node_modules\@oai\sky\bin\windows'
$helper = Join-Path $helperDirectory 'codex-computer-use.exe'
$manifest = Join-Path $pluginRoot '26.test\.mcp.json'
try {
    New-Item -ItemType Directory -Path $helperDirectory, (Split-Path -Parent $manifest), (Join-Path $runtimeRoot 'newer-but-unused') -Force | Out-Null
    Set-Content -LiteralPath $helper -Value 'fixture helper'
    $command = Join-Path $runtime 'bin\node.exe'
    Set-Content -LiteralPath $command -Value 'fixture node'
    @{ mcpServers = @{ cua_repl = @{ command = $command } } } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $manifest -Encoding utf8
    $arguments = @{ RuntimeRoot = $runtimeRoot; PluginRoot = $pluginRoot; Json = $true }
    $state = & $manager status @arguments | ConvertFrom-Json
    if ($state.runtimeId -ne 'configured' -or $state.runtimeSelection -ne 'plugin-command') { throw 'Runtime must come from the launch command, not the newest directory.' }
    if ($state.captureCompatibility[0].state -ne 'not-installed-needs-validation') { throw 'DLL absence is not a functional failure.' }

    $skyPath = Join-Path $runtime 'bin\node_modules\@oai\sky\sky.js'
    Set-Content -LiteralPath $skyPath -Value 'stock sky'
    $before = (Get-FileHash -LiteralPath $skyPath).Hash
    & $manager install -RuntimeRoot $runtimeRoot -PluginRoot $pluginRoot | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $helperDirectory 'version.dll'))) { throw 'Capture DLL was not installed.' }
    if ((Get-FileHash -LiteralPath $skyPath).Hash -ne $before) { throw 'Installation changed the stock script.' }
    $state = & $manager status @arguments | ConvertFrom-Json
    if ($state.captureCompatibility[0].state -ne 'installed-and-owned') { throw 'Owned DLL was not recognized.' }
    Set-Content -LiteralPath $helper -Value 'updated helper'
    $state = & $manager status @arguments | ConvertFrom-Json
    if ($state.captureCompatibility[0].state -ne 'helper-changed-needs-validation') { throw 'Changed helper must require validation.' }
    & $manager uninstall -HelperPath $helper | Out-Null

    $secondCommand = Join-Path $runtimeRoot 'newer-but-unused\bin\node.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $secondCommand) -Force | Out-Null
    Set-Content -LiteralPath $secondCommand -Value 'second node'
    @{ mcpServers = @{ one = @{ command = $command }; two = @{ command = $secondCommand } } } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest -Encoding utf8
    $state = & $manager status @arguments | ConvertFrom-Json
    if ($state.runtimeSelection -ne 'selection-required' -or $state.captureCompatibility.Count) { throw 'Ambiguous runtimes must not be silently selected.' }
    $state = & $manager status @arguments -HelperPath $helper | ConvertFrom-Json
    if ($state.captureCompatibility[0].helperPath -ne $helper) { throw 'Explicit helper was ignored.' }
    'PASS: configured runtime selection, ambiguity, explicit helper, DLL-only install and helper-change classification.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $project 'capture-compat\validation')) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
