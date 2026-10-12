[CmdletBinding()]
param(
    [string]$ManifestRoot = "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\unified-computer-use",
    [switch]$Check,
    [switch]$Native
)
$ErrorActionPreference = 'Stop'

# The desktop app rewrites this manifest with the runtime selected for this start.
# Read its transport and environment instead of pinning a runtime or editing it.
$candidates = @()
foreach ($file in Get-ChildItem -LiteralPath $ManifestRoot -Filter .mcp.json -Recurse -File) {
    $manifest = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $server = $manifest.mcpServers.cua_repl
    if (-not $server -or $server.enabled -eq $false) { continue }
    $arguments = @($server.args)
    if ([IO.Path]::GetFileName([string]$server.command) -ine 'node.exe' -or
        $arguments.Count -ne 1 -or
        [string]$arguments[0] -notmatch '\\node_modules\\@oai\\cua-repl\\bin\\cua-repl\.mjs$') { continue }
    if (-not (Test-Path -LiteralPath $server.command -PathType Leaf) -or
        -not (Test-Path -LiteralPath $arguments[0] -PathType Leaf)) { continue }
    $candidates += [pscustomobject]@{ manifest=$file.FullName; server=$server }
}
if ($candidates.Count -ne 1) {
    throw "Expected one current official CUA manifest; found $($candidates.Count). No process started."
}
$selected = $candidates[0]
$server = $selected.server
$proxyKeys = @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY')
$inheritedProxy = @{}
foreach ($key in $proxyKeys) {
    $value = [Environment]::GetEnvironmentVariable($key, 'Process')
    if ($null -ne $value) { $inheritedProxy[$key] = $value }
}
if (-not ($inheritedProxy.HTTP_PROXY -or $inheritedProxy.HTTPS_PROXY -or $inheritedProxy.ALL_PROXY)) {
    throw 'CUA did not receive the existing proxy environment from Codex. No process started.'
}
$info = [Diagnostics.ProcessStartInfo]::new()
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.FileName = $server.command
foreach ($argument in $server.args) { $info.ArgumentList.Add([string]$argument) }
foreach ($entry in $server.env.psobject.Properties) {
    $info.Environment[$entry.Name] = [string]$entry.Value
}
foreach ($key in $inheritedProxy.Keys) { $info.Environment[$key] = $inheritedProxy[$key] }
$info.Environment['NODE_USE_ENV_PROXY'] = '1'
if ($Native) {
    $info.FileName = $server.env.CUA_REPL_NODE_REPL_PATH
    if (-not (Test-Path -LiteralPath $info.FileName -PathType Leaf)) { throw 'Current official native Node REPL executable is unavailable.' }
    $info.ArgumentList.Clear()
    $services = $server.env.NODE_REPL_TRUSTED_SERVICES | ConvertFrom-Json -AsHashtable
    $services.sky = '@oai/sky/service'
    $info.Environment['NODE_REPL_TRUSTED_SERVICES'] = $services | ConvertTo-Json -Compress
}
if ($Check) {
    [pscustomobject]@{
        manifest = $selected.manifest
        command = $info.FileName
        args = @($info.ArgumentList)
        forwardedProxyKeys = @($inheritedProxy.Keys | Sort-Object)
        officialEnvironmentKeys = @($server.env.psobject.Properties.Name)
    } | ConvertTo-Json -Depth 4
    return
}
# Forward bytes without interpreting MCP messages or using PowerShell pipelines.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading.Tasks;
public static class CuaProxyStreams {
    static async Task Pump(Stream source, Stream target) {
        byte[] buffer = new byte[8192];
        int count;
        while ((count = await source.ReadAsync(buffer, 0, buffer.Length)) != 0) {
            await target.WriteAsync(buffer, 0, count);
            await target.FlushAsync();
        }
    }
    static async Task Input(Process child) {
        try { await Pump(Console.OpenStandardInput(), child.StandardInput.BaseStream); }
        catch (IOException) { }
        finally { child.StandardInput.Close(); }
    }
    public static async Task<int> Run(Process child) {
        Task input = Input(child);
        Task output = Pump(child.StandardOutput.BaseStream, Console.OpenStandardOutput());
        Task error = Pump(child.StandardError.BaseStream, Console.OpenStandardError());
        await child.WaitForExitAsync();
        await Task.WhenAll(output, error);
        return child.ExitCode;
    }
}
'@
$info.RedirectStandardInput = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$child = [Diagnostics.Process]::Start($info)
try { $exitCode = [CuaProxyStreams]::Run($child).GetAwaiter().GetResult() } finally { $child.Dispose() }
exit $exitCode
