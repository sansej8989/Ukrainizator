# ============================================================
# Ukrainian Language Installation and Keyboard Setup Script
# With Admin Check, Internet Check, Progress, Sound, and Language Mode
# ============================================================

# ===========================
# Configuration
$LanguageMode = "UA" # UA = Ukrainian, EN = English

function Show-Message($msgUA, $msgEN) {
    if ($LanguageMode -eq "UA") { Write-Host $msgUA }
    else { Write-Host $msgEN }
}

# ===========================
# 1. Check for Administrator (must be first!)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    [console]::beep(800,300)
    Write-Host "ERROR: Скрипт потрібно запускати від адміністратора!" -ForegroundColor Red
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

# ===========================
# 2. Check PowerShell version
$PSVersionNeeded = 5.1
if ($PSVersionTable.PSVersion.Major -lt [math]::Floor($PSVersionNeeded)) {
    [console]::beep(800,300)
    Show-Message "Потрібна PowerShell версія 5.1 або новіша!" "PowerShell version 5.1 or higher is required!"
    exit 1
}

# ===========================
# 3. Check Internet
Show-Message "Перевірка підключення до інтернету..." "Checking internet connection..."
$internetAvailable = Test-Connection -ComputerName www.microsoft.com -Count 2 -Quiet
if (-not $internetAvailable) {
    [console]::beep(800,300)
    Show-Message "Інтернет не доступний! Скрипт завершено." "Internet not available! Script terminated."
    exit 1
}

# ===========================
# 4. Install Ukrainian language
Write-Progress -Activity "Installing Language Pack" -Status "uk-UA..." -PercentComplete 10
[console]::beep(1000,200)
Install-Language -Language "uk-UA" -CopyToSettings -ExcludeFeatures
Write-Progress -Activity "Installing Language Pack" -Status "uk-UA complete" -PercentComplete 30
[console]::beep(1200,200)

# ===========================
# 5. Set system UI language
Write-Progress -Activity "Setting System UI Language" -Status "uk-UA..." -PercentComplete 40
[console]::beep(1000,200)
Set-SystemPreferredUILanguage -Language "uk-UA"
Write-Progress -Activity "Setting System UI Language" -Status "Completed" -PercentComplete 60
[console]::beep(1200,200)

# ===========================
# 6. Configure keyboard layouts
Write-Progress -Activity "Configuring Keyboard Layouts" -Status "Reading current layout..." -PercentComplete 70
[console]::beep(1000,200)

$currentList = Get-WinUserLanguageList
$newList = @()

# Ukrainian first
if (-not ($currentList.LanguageTag -contains "uk-UA")) { $newList += New-WinUserLanguageList -Language "uk-UA" }
else { $newList += ($currentList | Where-Object {$_.LanguageTag -eq "uk-UA"}) }

# English second
if (-not ($currentList.LanguageTag -contains "en-US")) { $newList += New-WinUserLanguageList -Language "en-US" }
else { $newList += ($currentList | Where-Object {$_.LanguageTag -eq "en-US"}) }

Write-Progress -Activity "Configuring Keyboard Layouts" -Status "Applying layout order..." -PercentComplete 90
Set-WinUserLanguageList $newList -Force
[console]::beep(1500,200)

# ===========================
# 7. Done
Write-Progress -Activity "All Done" -Status "Completed" -PercentComplete 100
[console]::beep(2000,300)
Show-Message "Усі кроки виконано. Рекомендовано перезавантаження." "All steps completed. Manual restart is recommended."

# ============================================================
