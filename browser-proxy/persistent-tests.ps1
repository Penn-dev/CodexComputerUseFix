param([Parameter(Mandatory)][string]$NodePath)
$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path -Parent $PSScriptRoot) ('capture-compat\validation\persistent-proxy-' + [Guid]::NewGuid().ToString('N'))
$manifestRoot = Join-Path $root 'plugin'
$manifestPath = Join-Path $manifestRoot 'current\.mcp.json'
$shellPath = (Get-Process -Id $PID).Path
$proxyValues = @{HTTP_PROXY='http://127.0.0.1:7890';HTTPS_PROXY='http://127.0.0.1:7890';ALL_PROXY='http://127.0.0.1:7890';NO_PROXY='localhost,127.0.0.1,::1,custom.internal'}
function Run-Launcher {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $shellPath; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($arg in @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'launch.ps1'),'-ManifestRoot',$manifestRoot)) { $info.ArgumentList.Add($arg) }
    foreach ($key in $proxyValues.Keys) { $info.Environment[$key] = $proxyValues[$key] }
    $child = [Diagnostics.Process]::Start($info)
    try {
        $child.StandardInput.WriteLine('{"method":"test"}')
        $firstLine = $child.StandardOutput.ReadLineAsync()
        if (-not $firstLine.Wait(5000)) { $child.Kill($true); throw 'MCP response did not arrive while stdin remained open.' }
        $stdout = $firstLine.GetAwaiter().GetResult()
        $child.StandardInput.WriteLine('{"method":"second"}')
        $secondLine = $child.StandardOutput.ReadLineAsync()
        if (-not $secondLine.Wait(5000)) { $child.Kill($true); throw 'Second MCP response did not arrive.' }
        $second = $secondLine.GetAwaiter().GetResult() | ConvertFrom-Json
        if ($second.input.method -ne 'second') { throw 'Streaming request was not forwarded.' }
        $child.StandardInput.Close()
        $errorTask = $child.StandardError.ReadToEndAsync()
        if (-not $child.WaitForExit(10000)) { $child.Kill($true); $child.WaitForExit(); throw 'Launcher test timed out.' }
        $stderr = $errorTask.GetAwaiter().GetResult()
        if ($child.ExitCode -ne 0) { throw "Launcher failed: $stderr" }
        return $stdout | ConvertFrom-Json
    } finally { $child.Dispose() }
}
try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force | Out-Null
    foreach ($version in @('runtime-a','runtime-b')) {
        $bin = Join-Path $root "$version\bin"
        $launcher = Join-Path $bin 'node_modules\@oai\cua-repl\bin\cua-repl.mjs'
        New-Item -ItemType Directory -Path (Split-Path -Parent $launcher) -Force | Out-Null
        Copy-Item -LiteralPath $NodePath -Destination (Join-Path $bin 'node.exe')
        $code = @'
let input = ''; process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  input += chunk; let newline;
  while ((newline = input.indexOf('\n')) >= 0) {
    const request = JSON.parse(input.slice(0, newline)); input = input.slice(newline + 1);
    console.log(JSON.stringify({input:request,runtime:process.env.OFFICIAL_RUNTIME,proxy:process.env.HTTP_PROXY,noProxy:process.env.NO_PROXY,nodeProxy:process.env.NODE_USE_ENV_PROXY,official:process.env.NODE_REPL_TRUSTED_SERVICES}));
  }
});
'@
        [IO.File]::WriteAllText($launcher,$code,[Text.UTF8Encoding]::new($false))
        $manifest = @{mcpServers=@{cua_repl=@{command=(Join-Path $bin 'node.exe');args=@($launcher);env=@{OFFICIAL_RUNTIME=$version;NODE_REPL_TRUSTED_SERVICES='preserved-official-reference'}}}}
        [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        $hashBefore = (Get-FileHash -LiteralPath $launcher).Hash
        $result = Run-Launcher
        if ($result.runtime -ne $version -or $result.input.method -ne 'test' -or $result.proxy -ne $proxyValues.HTTP_PROXY -or $result.noProxy -ne $proxyValues.NO_PROXY -or $result.nodeProxy -ne '1' -or $result.official -ne 'preserved-official-reference') { throw 'Runtime, proxy, official environment or stdio was not preserved.' }
        if ((Get-FileHash -LiteralPath $launcher).Hash -ne $hashBefore) { throw 'Official runtime was modified.' }
    }
    $config = Join-Path $root 'config.toml'
    $original = "[mcp_servers.other]`ncommand = 'existing.exe'`n"
    [IO.File]::WriteAllText($config,$original,[Text.UTF8Encoding]::new($false))
    & (Join-Path $PSScriptRoot 'persistent.ps1') -ConfigPath $config | Out-Null
    & (Join-Path $PSScriptRoot 'persistent.ps1') -ConfigPath $config | Out-Null
    $installed = [IO.File]::ReadAllText($config)
    $installedLauncher = Join-Path $root 'codex-cu-browser-proxy-launch.ps1'
    $ownedRecordPath = "$config.codex-cu-browser-proxy.json"
    $ownedRecord = Get-Content -LiteralPath $ownedRecordPath -Raw | ConvertFrom-Json
    Add-Content -LiteralPath $installedLauncher -Value '# previous recorded launcher'
    $ownedRecord.launcherHash = (Get-FileHash -LiteralPath $installedLauncher).Hash
    [IO.File]::WriteAllText($ownedRecordPath,($ownedRecord | ConvertTo-Json))
    $oldHash = $ownedRecord.launcherHash
    & (Join-Path $PSScriptRoot 'persistent.ps1') -ConfigPath $config -Action Update | Out-Null
    if ((Get-FileHash -LiteralPath "$installedLauncher.previous").Hash -ne $oldHash -or
        (Get-FileHash -LiteralPath $installedLauncher).Hash -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'launch.ps1')).Hash -or
        [IO.File]::ReadAllText($config) -ne $installed) { throw 'Owned launcher update lost its rollback copy or changed configuration.' }
    [IO.File]::WriteAllText($config,$installed.Replace("startup_timeout_sec = 120","startup_timeout_sec = 121"),[Text.UTF8Encoding]::new($false))
    $rejected = $false
    try { & (Join-Path $PSScriptRoot 'persistent.ps1') -ConfigPath $config -Action Uninstall | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Changed owned configuration was overwritten.' }
    [IO.File]::WriteAllText($config,$installed+"`n# another later edit`n",[Text.UTF8Encoding]::new($false))
    & (Join-Path $PSScriptRoot 'persistent.ps1') -ConfigPath $config -Action Uninstall | Out-Null
    if ([IO.File]::ReadAllText($config) -ne $original+"`n# another later edit`n") { throw 'Uninstall changed unrelated configuration.' }
    Write-Output 'PASS: runtime change, inherited MCP stdio, proxy and bypass preservation, unchanged runtime, idempotency and protected configuration restore.'
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    $expected = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'capture-compat\validation')) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected test directory.' }
    for ($attempt=0; $attempt -lt 10 -and (Test-Path -LiteralPath $resolved); $attempt++) {
        try { Remove-Item -LiteralPath $resolved -Recurse -Force }
        catch [IO.IOException] {
            if ($attempt -eq 9) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}
