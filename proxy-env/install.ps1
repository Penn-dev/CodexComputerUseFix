[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$LauncherPath,
    [ValidateSet('Install','Uninstall')][string]$Action = 'Install',
    [string]$ProxyUrl = 'http://127.0.0.1:7890'
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $LauncherPath).Path
if ([IO.Path]::GetFileName($source) -cne 'cua-repl.mjs' -or $source -notmatch '\\node_modules\\@oai\\cua-repl\\bin\\') {
    throw 'LauncherPath must point to @oai/cua-repl/bin/cua-repl.mjs.'
}
$marker = 'codex-cu-proxy-env:v2'
$legacyMarker = 'codex-cu-proxy-env:v1'
$backup = "$source.codex-cu-proxy-env.bak"
$recordPath = "$source.codex-cu-proxy-env.install.json"
$needle = 'import * as cua_repl from "@oai/cua-repl";'
$proxyLiteral = ConvertTo-Json -InputObject $ProxyUrl -Compress
$replacement = @"
import http from "node:http";
/* codex-cu-proxy-env:v2 */
Object.assign(process.env, {
  NODE_USE_ENV_PROXY: "1",
  HTTP_PROXY: $proxyLiteral,
  HTTPS_PROXY: $proxyLiteral,
  http_proxy: $proxyLiteral,
  https_proxy: $proxyLiteral,
  NO_PROXY: "localhost,127.0.0.1,::1",
  no_proxy: "localhost,127.0.0.1,::1",
});
http.setGlobalProxyFromEnv();
const cua_repl = await import("@oai/cua-repl");
"@
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

if ($Action -eq 'Install') {
    $content = [IO.File]::ReadAllText($source)
    if ($content.Contains($marker)) {
        if (-not (Test-Path -LiteralPath $recordPath)) { throw 'Proxy marker exists without an ownership record.' }
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        if (-not [string]::Equals($record.sourcePath, $source, [StringComparison]::OrdinalIgnoreCase) -or (Get-Hash $source) -ne $record.patchedSha256) {
            throw 'Installed launcher does not match the proxy injection record.'
        }
        Write-Output 'CU proxy environment injection is already installed.'
        return
    }
    if ($content.Contains($legacyMarker)) { throw 'Version 1 is installed. Uninstall it before installing version 2.' }
    if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $recordPath)) { throw 'Unowned proxy injection backup or record already exists.' }
    if (([regex]::Matches($content, [regex]::Escape($needle))).Count -ne 1) { throw 'Unsupported cua-repl launcher import.' }
    if ($PSCmdlet.ShouldProcess($source, "Inject proxy environment $ProxyUrl")) {
        Copy-Item -LiteralPath $source -Destination $backup
        $originalHash = Get-Hash $backup
        [IO.File]::WriteAllText($source, $content.Replace($needle, $replacement), $utf8)
        $patchedHash = Get-Hash $source
        if (-not ([IO.File]::ReadAllText($source).Contains($marker)) -or $patchedHash -eq $originalHash) {
            Copy-Item -LiteralPath $backup -Destination $source -Force
            Remove-Item -LiteralPath $backup -Force
            throw 'Proxy injection verification failed; original launcher restored.'
        }
        [pscustomobject]@{
            sourcePath = $source
            proxyUrl = $ProxyUrl
            originalSha256 = $originalHash
            patchedSha256 = $patchedHash
            installedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $recordPath -Encoding utf8
        Write-Output "Installed CU proxy environment injection: $source"
    }
    return
}

if (-not (Test-Path -LiteralPath $recordPath) -or -not (Test-Path -LiteralPath $backup)) {
    $content = [IO.File]::ReadAllText($source)
    if (-not $content.Contains($marker) -and -not $content.Contains($legacyMarker)) { Write-Output 'CU proxy environment injection is not installed.'; return }
    throw 'Proxy injection ownership files are incomplete; refusing to modify the launcher.'
}
$record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
if (-not [string]::Equals($record.sourcePath, $source, [StringComparison]::OrdinalIgnoreCase)) { throw 'Proxy injection record targets a different launcher.' }
if ((Get-Hash $source) -ne $record.patchedSha256) { throw 'Launcher changed after proxy injection; refusing to overwrite it.' }
if ((Get-Hash $backup) -ne $record.originalSha256) { throw 'Proxy injection backup hash mismatch.' }
if ($PSCmdlet.ShouldProcess($source, 'Remove proxy environment injection')) {
    Copy-Item -LiteralPath $backup -Destination $source -Force
    if ((Get-Hash $source) -ne $record.originalSha256) { throw 'Restored launcher hash mismatch.' }
    Remove-Item -LiteralPath $backup -Force
    Remove-Item -LiteralPath $recordPath -Force
    Write-Output "Removed CU proxy environment injection: $source"
}
