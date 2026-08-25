# bootstrap.ps1 - downloads a SPECIFIC release of Ukrainizator (not the
# moving main branch) into a temp folder, verifies the archive checksum,
# and runs the real ukrainizator.ps1 from disk.
#
# Usage:
#   irm https://sansej8989.github.io/Ukrainizator/bootstrap.ps1 | iex
#
# NOTE: this file is deliberately ASCII-only (no Cyrillic). When fetched
# via irm/Invoke-RestMethod, PowerShell 5.1 decodes the response using the
# server's declared charset - and GitHub Pages does not always declare
# charset=utf-8 for .ps1 files, so non-ASCII bytes can get misdecoded and
# break parsing before the script even runs. ASCII bytes are identical in
# every common encoding, so this sidesteps the problem entirely. All the
# actual Ukrainian UI lives in ukrainizator.ps1 itself, which is run as a
# real local file (with a proper UTF-8 BOM) once downloaded - unaffected.

$ErrorActionPreference = 'Stop'

$repoOwner  = 'sansej8989'
$repoName   = 'Ukrainizator'
$destRoot   = Join-Path $env:TEMP 'Ukrainizator'
$zipPath    = Join-Path $env:TEMP 'ukrainizator_dl.zip'
# Fallback mirror if GitHub itself is unreachable (network restrictions).
# jsDelivr mirrors public GitHub repos; no separate checksum file is
# available there, so integrity verification is skipped on this path -
# a deliberate "still runs" vs "fully verified" tradeoff.
$fallbackBaseUrl = "https://cdn.jsdelivr.net/gh/$repoOwner/$repoName@main"

function Get-LatestReleaseInfo {
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
    return Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'Ukrainizator-Bootstrap' } -TimeoutSec 10
}

function Install-FromRelease {
    Write-Host 'Checking latest release...' -ForegroundColor Cyan
    $release = Get-LatestReleaseInfo
    $zipAsset  = $release.assets | Where-Object { $_.name -eq 'Ukrainizator.zip' }
    $hashAsset = $release.assets | Where-Object { $_.name -eq 'Ukrainizator.zip.sha256' }

    if (-not $zipAsset) { throw 'Ukrainizator.zip not found in the latest release' }

    Write-Host "Downloading release $($release.tag_name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing

    if ($hashAsset) {
        Write-Host 'Verifying archive checksum...' -ForegroundColor Cyan
        $expectedHash = (Invoke-RestMethod -Uri $hashAsset.browser_download_url -TimeoutSec 10).Trim().ToUpper()
        $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpper()
        if ($expectedHash -ne $actualHash) {
            throw "Archive checksum mismatch! Expected: $expectedHash, got: $actualHash. Aborting."
        }
        Write-Host 'Checksum OK.' -ForegroundColor DarkGreen
    } else {
        Write-Host 'No checksum file in this release - skipping verification.' -ForegroundColor DarkYellow
    }

    return $release.tag_name
}

function Install-FromMirror {
    Write-Host 'GitHub unavailable - trying fallback mirror (jsDelivr)...' -ForegroundColor DarkYellow
    New-Item -ItemType Directory -Path (Join-Path $destRoot 'locales') -Force | Out-Null

    Invoke-WebRequest -Uri "$fallbackBaseUrl/ukrainizator.ps1" -OutFile (Join-Path $destRoot 'ukrainizator.ps1') -UseBasicParsing
    Invoke-WebRequest -Uri "$fallbackBaseUrl/locales/uk-UA.json" -OutFile (Join-Path $destRoot 'locales/uk-UA.json') -UseBasicParsing
    Invoke-WebRequest -Uri "$fallbackBaseUrl/locales/en-US.json" -OutFile (Join-Path $destRoot 'locales/en-US.json') -UseBasicParsing
    Write-Host 'Downloaded via fallback mirror (unverified).' -ForegroundColor DarkYellow
    return 'main (mirror, unverified)'
}

if (Test-Path $destRoot) { Remove-Item $destRoot -Recurse -Force }
New-Item -ItemType Directory -Path $destRoot -Force | Out-Null

$usedVersion = $null
try {
    $usedVersion = Install-FromRelease
    Expand-Archive -Path $zipPath -DestinationPath $destRoot -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Could not download release from GitHub: $($_.Exception.Message)" -ForegroundColor Red
    try {
        $usedVersion = Install-FromMirror
    } catch {
        Write-Host "Fallback mirror also unavailable: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Check your internet connection and try again.' -ForegroundColor Red
        exit 1
    }
}

$scriptPath = Join-Path $destRoot 'ukrainizator.ps1'
if (-not (Test-Path $scriptPath)) {
    # Release-archive path extracts into a subfolder (e.g. Ukrainizator\Ukrainizator\)
    $innerFolder = Get-ChildItem -Path $destRoot -Directory | Select-Object -First 1
    if ($innerFolder) { $scriptPath = Join-Path $innerFolder.FullName 'ukrainizator.ps1' }
}

if (-not (Test-Path $scriptPath)) {
    Write-Host 'Could not find ukrainizator.ps1 after download.' -ForegroundColor Red
    exit 1
}

Write-Host "Launching version: $usedVersion" -ForegroundColor DarkGreen
& $scriptPath @args
