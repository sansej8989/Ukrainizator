# bootstrap.ps1 - завантажує КОНКРЕТНИЙ реліз Українізатора (не гілку main,
# яка може змінюватись у будь-яку мить) у тимчасову теку, перевіряє
# контрольну суму архіву і запускає справжній ukrainizator.ps1 з диска.
#
# Використання:
#   irm https://sansej8989.github.io/Ukrainizator/bootstrap.ps1 | iex

$ErrorActionPreference = 'Stop'

$repoOwner  = 'sansej8989'
$repoName   = 'Ukrainizator'
$destRoot   = Join-Path $env:TEMP 'Ukrainizator'
$zipPath    = Join-Path $env:TEMP 'ukrainizator_dl.zip'
# Якщо GitHub API недоступний (мережеві обмеження) - резервний шлях через
# jsDelivr (окремий CDN, що дзеркалить публічні GitHub-репозиторії; не
# завжди має ідентичний хеш-файл, тому тут перевірка контрольної суми
# пропускається - це свідомий компроміс "хоч якось запуститись" проти
# "гарантовано перевірено").
$fallbackBaseUrl = "https://cdn.jsdelivr.net/gh/$repoOwner/$repoName@main"

function Get-LatestReleaseInfo {
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
    return Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'Ukrainizator-Bootstrap' } -TimeoutSec 10
}

function Install-FromRelease {
    Write-Host 'Перевірка останнього релізу...' -ForegroundColor Cyan
    $release = Get-LatestReleaseInfo
    $zipAsset  = $release.assets | Where-Object { $_.name -eq 'Ukrainizator.zip' }
    $hashAsset = $release.assets | Where-Object { $_.name -eq 'Ukrainizator.zip.sha256' }

    if (-not $zipAsset) { throw 'У релізі не знайдено файл Ukrainizator.zip' }

    Write-Host "Завантаження релізу $($release.tag_name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing

    if ($hashAsset) {
        Write-Host 'Перевірка контрольної суми архіву...' -ForegroundColor Cyan
        $expectedHash = (Invoke-RestMethod -Uri $hashAsset.browser_download_url -TimeoutSec 10).Trim().ToUpper()
        $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpper()
        if ($expectedHash -ne $actualHash) {
            throw "Контрольна сума архіву НЕ збігається! Очікувано: $expectedHash, отримано: $actualHash. Завантаження скасовано."
        }
        Write-Host 'Контрольна сума збігається - файл цілий.' -ForegroundColor DarkGreen
    } else {
        Write-Host 'Файл контрольної суми відсутній у релізі - перевірку пропущено.' -ForegroundColor DarkYellow
    }

    return $release.tag_name
}

function Install-FromMirror {
    # Запасний шлях: качаємо потрібні файли поштучно напряму з jsDelivr,
    # без перевірки хешу (жодного .sha256 там немає) - лише щоб скрипт
    # взагалі зміг запуститись, якщо GitHub недоступний.
    Write-Host 'GitHub недоступний - пробуємо резервне дзеркало (jsDelivr)...' -ForegroundColor DarkYellow
    $innerDir = Join-Path $destRoot 'Ukrainizator'
    New-Item -ItemType Directory -Path (Join-Path $innerDir 'locales') -Force | Out-Null

    Invoke-WebRequest -Uri "$fallbackBaseUrl/ukrainizator.ps1" -OutFile (Join-Path $innerDir 'ukrainizator.ps1') -UseBasicParsing
    Invoke-WebRequest -Uri "$fallbackBaseUrl/locales/uk-UA.json" -OutFile (Join-Path $innerDir 'locales/uk-UA.json') -UseBasicParsing
    Invoke-WebRequest -Uri "$fallbackBaseUrl/locales/en-US.json" -OutFile (Join-Path $innerDir 'locales/en-US.json') -UseBasicParsing
    Write-Host 'Завантажено через резервне дзеркало (без перевірки хешу).' -ForegroundColor DarkYellow
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
    Write-Host "Не вдалося завантажити реліз через GitHub: $($_.Exception.Message)" -ForegroundColor Red
    try {
        $usedVersion = Install-FromMirror
    } catch {
        Write-Host "Резервне дзеркало теж недоступне: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Перевірте інтернет-з''єднання і спробуйте ще раз.' -ForegroundColor Red
        exit 1
    }
}

$innerFolder = Get-ChildItem -Path $destRoot -Directory | Select-Object -First 1
$scriptPath = Join-Path $innerFolder.FullName 'ukrainizator.ps1'

if (-not (Test-Path $scriptPath)) {
    Write-Host 'Не вдалося знайти ukrainizator.ps1 після завантаження.' -ForegroundColor Red
    exit 1
}

Write-Host "Запуск версії: $usedVersion" -ForegroundColor DarkGreen
& $scriptPath @args
