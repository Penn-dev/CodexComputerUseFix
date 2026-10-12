[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArchivePath)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$archivePath = (Resolve-Path -LiteralPath $ArchivePath).Path
$archiveName = [IO.Path]::GetFileName($archivePath)
$checksum = (Get-Content -LiteralPath "$archivePath.sha256" -Raw).Trim()
$expectedHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($checksum -cne "$expectedHash  $archiveName") { throw 'Archive checksum does not match.' }

$fixture = Join-Path $project ('validation/package-fixture-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        if ($name -match '(^|/)\.\.(/|$)|^/|^[A-Za-z]:') { throw "Unsafe archive path: $name" }
        if ($name -match '(^|/)(build|validation|\.git|codex-win10-capture-compat)(/|$)|(^|/)migration-manifest\.json$') {
            throw "Local or generated data included in archive: $name"
        }
    }
} finally { $archive.Dispose() }
[IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $fixture)

foreach ($name in @('version.dll', 'compat_probe.exe', 'capture_test_window.exe')) {
    $packaged = Join-Path $fixture "capture-compat/dist/$name"
    if ((Get-FileHash -LiteralPath $packaged).Hash -ne (Get-FileHash -LiteralPath (Join-Path $project "dist/$name")).Hash) {
        throw "Packaged binary differs from build output: $name"
    }
}
foreach ($relative in @('LICENSE', 'README.md', 'README_en.md', 'manage.ps1', 'docs/cu-maintenance-audit.md', 'capture-compat/install.ps1', 'capture-compat/build.ps1', 'capture-compat/validate.ps1', 'native-runtime/install.ps1', 'native-runtime/bootstrap.mjs', 'native-runtime/worker-wrapper.cjs', 'capture-notify/health.mjs', 'capture-notify/notify.mjs', 'windows-lifecycle/install.ps1', 'windows-lifecycle/lifecycle.mjs', 'windows-lifecycle/tests.mjs', 'browser-proxy/launch.ps1', 'browser-proxy/persistent.ps1', 'browser-proxy/persistent-tests.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $fixture $relative) -PathType Leaf)) { throw "Missing package file: $relative" }
}

# Verify documentation from the extracted layout, not from the source tree.
if (Test-Path -LiteralPath (Join-Path $fixture 'capture-compat/monitor.ps1')) {
    throw 'Retired polling monitor was packaged.'
}
$linksChecked = 0
Get-ChildItem -LiteralPath $fixture -Filter *.md -File -Recurse | ForEach-Object {
    $document = $_
    $text = Get-Content -LiteralPath $document.FullName -Raw
    # Code examples can contain PowerShell [type](expression), which is not a link.
    $text = [regex]::Replace($text, '(?ms)^```[^\r\n]*\r?\n.*?^```[^\r\n]*(?:\r?\n|$)', '')
    foreach ($link in [regex]::Matches($text, '\[[^\]\r\n]+\]\(([^)\r\n]+)\)')) {
        $target = $link.Groups[1].Value
        if ($target -match '^(https?://|codex://|mailto:|#)') { continue }
        $path = Join-Path $document.DirectoryName ($target -split '#', 2)[0]
        if (-not (Test-Path -LiteralPath $path)) { throw "Broken packaged link in $($document.Name): $target" }
        $linksChecked++
    }
}
& (Join-Path $fixture 'capture-compat/tests/install_tests.ps1')
"PASS: archive checksum, binary hashes, layout, $linksChecked documentation links, and installation from extracted package."
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $validationPrefix = [IO.Path]::GetFullPath((Join-Path $project 'validation')) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith($validationPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected package test cleanup target.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
