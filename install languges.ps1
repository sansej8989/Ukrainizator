# Ukrainizator v1.6.0
# ============================================================
# Встановлення української мови Windows
# ============================================================

#region === Налаштування ===
$scriptVersion = '1.6.0'
$logFile = Join-Path $env:TEMP "Ukrainizator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$startTime = Get-Date

function Write-Log {
    param([string]$Message, [string]$Color = 'White')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    if ($Color -ne 'White') { Write-Host $logMessage -ForegroundColor $Color }
    else { Write-Host $logMessage }
}

function Write-Step {
    param([string]$Title, [string]$Message = '')
    Write-Host ''
    Write-Host "$Title" -ForegroundColor Cyan -NoNewline
    if ($Message) { Write-Host " - $Message" -ForegroundColor Gray }
    else { Write-Host '' }
    Write-Log "> $Title" -Color Cyan
}

function Show-ProgressBar {
    param([int]$Percent, [string]$Label = '')
    $barSize = 30
    $filled = [math]::Floor($Percent / 100 * $barSize)
    $empty = $barSize - $filled
    $bar = [char]9608 * $filled + [char]9617 * $empty
    if ($Label) { Write-Host "  $bar  $Percent%  $Label" -ForegroundColor Yellow }
    else { Write-Host "  $bar  $Percent%" -ForegroundColor Yellow }
    Write-Host ""
}

function Write-ErrorExit {
    param([string]$Message)
    [console]::beep(800,300)
    Write-Host "  [!] $Message" -ForegroundColor Red
    Write-Log "ПОМИЛКА: $Message" -Color Red
    exit 1
}

function Show-FlagHeader {
    Clear-Host
    $w = $host.UI.RawUI.WindowSize.Width
    if ($w -lt 40) { $w = 40 }
    Write-Host (' ' * $w) -BackgroundColor Blue
    Write-Host (' ' * $w) -BackgroundColor Blue
    Write-Host (' ' * $w) -BackgroundColor Yellow
    Write-Host (' ' * $w) -BackgroundColor Yellow
    Write-Host ''
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host '  UKRAINIZATOR  v1.6.0' -ForegroundColor Yellow
    Write-Host '  Встановлення української мови в Windows' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "Лог: $logFile" -ForegroundColor Gray
}
#endregion

#region === Заголовок ===
Show-FlagHeader
Write-Log "Запуск Ukrainizator v$scriptVersion"
#endregion
#region === 1. Перевірка прав ===
Show-FlagHeader
Write-Step '*** Крок 1/9 ***' 'Перевірка прав адміністратора'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-ErrorExit 'Потрібні права адміністратора! Запустіть від імені адміністратора.'
}
Write-Host '  [OK] Права адміністратора підтверджено.' -ForegroundColor Green
Write-Log 'Права адміністратора підтверджено' -Color Green
#endregion

#region === 2. Версія PowerShell ===
Show-FlagHeader
Write-Step '*** Крок 2/9 ***' 'Перевірка версії PowerShell'
Show-ProgressBar -Percent 10 -Label 'PowerShell'
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-ErrorExit "Потрібен PowerShell 5.1+ (поточна: $($PSVersionTable.PSVersion))"
}
Write-Host "  [OK] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
Write-Log "Версія PowerShell: $($PSVersionTable.PSVersion)" -Color Green
#endregion

#region === 3. Інтернет ===
Show-FlagHeader
Write-Step '*** Крок 3/9 ***' 'Перевірка підключення до Інтернету'
Show-ProgressBar -Percent 20 -Label 'Інтернет'
Write-Host '  Перевірка...' -NoNewline
$online = $false
try {
    $online = Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet -ErrorAction Stop
} catch {
    try { Invoke-WebRequest -Uri 'https://www.microsoft.com' -UseBasicParsing -ErrorAction Stop | Out-Null; $online = $true } catch {}
}
if (-not $online) {
    Write-ErrorExit 'Інтернет недоступний! Потрібне з''єднання для завантаження мовного пакета.'
}
Write-Host ' [OK]' -ForegroundColor Green
Write-Host '  [OK] Інтернет доступний.' -ForegroundColor Green
Write-Log 'Інтернет підтверджено' -Color Green
#endregion

#region === 4. Попередження ===
Show-FlagHeader
Write-Step '*** Крок 4/9 ***' 'Попередження'
Show-ProgressBar -Percent 40 -Label 'Попередження'
Write-Host ''
Write-Host '  УВАГА: Скрипт змінює системну мову, мову інтерфейсу' -ForegroundColor Red
Write-Host '  та розкладки клавіатури для всіх користувачів.' -ForegroundColor Red
Write-Host '  Після завершення потрібне перезавантаження.' -ForegroundColor Red
Write-Host '  РЕКОМЕНДУЄТЬСЯ СТВОРИТИ ТОЧКУ ВІДНОВЛЕННЯ.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Продовжити? (Y/N): ' -NoNewline -ForegroundColor Yellow
$confirm = Read-Host
if ($confirm -notin @('Y','y','Yes','YES','ok','OK','yep')) {
    Write-Host '  Скасовано користувачем.' -ForegroundColor Red
    Write-Log 'Скасовано користувачем' -Color Red
    exit 1
}
Write-Host '  [OK] Продовжуємо...' -ForegroundColor Green
Write-Log 'Користувач підтвердив виконання' -Color Green
#endregion
#region === 5. Вибір режиму встановлення ===
Show-FlagHeader
Write-Step '*** Крок 5/9 ***' 'Вибір режиму встановлення'
Write-Host ''
Write-Host '  Застосувати для:' -ForegroundColor Yellow
Write-Host '    [A] Всіх користувачів (рекомендовано)' -ForegroundColor Cyan
Write-Host '    [C] Тільки поточного користувача' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Ваш вибір (A/C): ' -NoNewline -ForegroundColor Yellow
$installMode = Read-Host
if ($installMode -notin @('A','a','All','ALL')) {
    $installMode = 'Current'
    Write-Host '  [i] Вибрано: Тільки поточний користувач.' -ForegroundColor Gray
    Write-Log 'Вибрано режим: Тільки поточний користувач' -Color Gray
} else {
    $installMode = 'All'
    Write-Host '  [OK] Вибрано: Всіх користувачів.' -ForegroundColor Green
    Write-Log 'Вибрано режим: Всіх користувачів' -Color Green
}
Show-ProgressBar -Percent 45 -Label 'Режим вибрано'
#endregion
#region === 6. Модулі ===
Show-FlagHeader
Write-Step '*** Крок 6/9 ***' 'Перевірка системних модулів'
Show-ProgressBar -Percent 55 -Label 'Модулі'
Import-Module LanguagePackManagement -ErrorAction SilentlyContinue
if (-not (Get-Module -ListAvailable -Name LanguagePackManagement)) {
    Write-ErrorExit 'Модуль LanguagePackManagement недоступний. Переконайтеся, що система оновлена.'
}
Write-Host '  [OK] Модуль LanguagePackManagement завантажено.' -ForegroundColor Green
Write-Log 'Модуль LanguagePackManagement завантажено' -Color Green
#endregion

#region === 7. Мовний пакет ===
Show-FlagHeader
Write-Step '*** Крок 7/9 ***' 'Встановлення українського мовного пакета'
Show-ProgressBar -Percent 65 -Label 'Мовний пакет'
$ukUaInstalled = (Get-InstalledLanguage | Where-Object { $_.LanguageTag -eq 'uk-UA' })
if ($ukUaInstalled) {
    Write-Host '  [OK] uk-UA вже встановлено. Пропускаємо.' -ForegroundColor Yellow
    Write-Log 'uk-UA вже встановлено, пропускаємо' -Color Yellow
    Show-ProgressBar -Percent 70 -Label 'Вже встановлено'
} else {
    Write-Host '  Встановлення uk-UA...' -ForegroundColor Yellow
    Write-Log 'Початок встановлення uk-UA' -Color Yellow
    try {
        Install-Language -Language 'uk-UA' -CopyToSettings -ExcludeFeatures -ErrorAction Stop
        $ukUaInstalled = (Get-InstalledLanguage | Where-Object { $_.LanguageTag -eq 'uk-UA' })
        if (-not $ukUaInstalled) { Write-ErrorExit 'uk-UA не знайдено після інсталяції. Перевірте систему.' }
        Write-Host '  [OK] Мовний пакет встановлено.' -ForegroundColor Green
        Write-Log 'uk-UA встановлено успішно' -Color Green
    } catch { Write-ErrorExit "Не вдалося встановити мову: $($_.Exception.Message)" }
    Show-ProgressBar -Percent 70 -Label 'Встановлено'
}

Write-Host '  Налаштування мови інтерфейсу...' -ForegroundColor Yellow
try {
    Set-WinUILanguageOverride -Language 'uk-UA' -ErrorAction Stop
    Write-Host '  [OK] UI мову встановлено (після перезавантаження).' -ForegroundColor Green
    Write-Log 'UI мова uk-UA встановлена' -Color Green
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value '0422' -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value '0422' -ErrorAction Stop
    Write-Host '  [OK] Реєстр Nls\Language: Default+InstallLanguage=0422 (uk-UA).' -ForegroundColor Green
    Write-Log 'Реєстр Nls\Language: 0422' -Color Green
    if ($installMode -eq 'All') {
        Write-Host '  Копіювання на Welcome screen + нові користувачі...' -ForegroundColor Yellow
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $True -NewUser $True -ErrorAction Stop
            Write-Host '  [OK] Скопійовано: Welcome screen + нові користувачі.' -ForegroundColor Green
            Write-Log 'Скопійовано: WelcomeScreen+NewUser' -Color Green
        } catch {
            Write-Host "  [!] Copy-UserInternationalSettingsToSystem не спрацювало (можл. Win10): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Log "Копіювання: $($_.Exception.Message)" -Color Yellow
        }
        Write-Host ''
        Write-Host '  [!] Існуючі неактивні профілі НЕ змінені автоматично.' -ForegroundColor Red
        Write-Host '      Кожен користувач має увійти та налаштувати мову вручну.' -ForegroundColor Yellow
        Write-Log 'Існуючі неактивні профілі не змінені' -Color Red
    }
} catch {
    Write-Host '  [!] Не вдалося налаштувати UI мову (некритично):' -ForegroundColor Yellow
    Write-Host "     $($_.Exception.Message)" -ForegroundColor Gray
    Write-Log "UI мова: $($_.Exception.Message)" -Color Yellow
}
Show-ProgressBar -Percent 85 -Label 'Мова інтерфейсу'
#endregion
#region === 8. Розкладки ===
Show-FlagHeader
Write-Step '*** Крок 8/9 ***' 'Налаштування розкладок клавіатури'
Write-Host '  Встановлення: українська + англійська...' -ForegroundColor Yellow
try {
    $ll = New-WinUserLanguageList 'uk-UA'
    $ll[0].InputMethodTips.Clear()
    $ll[0].InputMethodTips.Add('0422:00000422')
    $ll[0].InputMethodTips.Add('0409:00000409')
    Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction Stop
    Write-Host '  [OK] Розкладки: укр (0422) + англ US (0409).' -ForegroundColor Green
    Write-Log 'Розкладки: 0422 + 0409' -Color Green
} catch {
    Write-Host '  [!] Не вдалося налаштувати клавіатуру (некритично):' -ForegroundColor Yellow
    Write-Host "     $($_.Exception.Message)" -ForegroundColor Gray
    Write-Log "Клавіатура: $($_.Exception.Message)" -Color Yellow
}
Show-ProgressBar -Percent 100 -Label 'Готово!'
#endregion

#region === 9. Завершення ===
Show-FlagHeader
Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '   ВСІ КРОКИ ВИКОНАНО!' -ForegroundColor Yellow
Write-Host '============================================' -ForegroundColor Green
$elapsed = (Get-Date) - $startTime
Write-Host "Час: $($elapsed.Minutes)хв $($elapsed.Seconds)сек" -ForegroundColor Gray
Write-Host "Лог: $logFile" -ForegroundColor Gray
Write-Host ''
Write-Host 'Перезавантажити зараз? (Y/N): ' -NoNewline -ForegroundColor Yellow
$reboot = Read-Host
if ($reboot -in @('Y','y','Yes','YES','ok','OK','yep')) {
    Write-Host '  Перезавантаження... До зустрічі!' -ForegroundColor Green
    Write-Log 'Перезавантаження за запитом користувача' -Color Green
    Start-Sleep -Seconds 2
    Restart-Computer
} else {
    Write-Host '  [i] Не забудьте перезавантажити пізніше.' -ForegroundColor Yellow
    Write-Host '  Дякуємо за використання Ukrainizator!' -ForegroundColor Cyan
    Write-Log 'Користувач відклав перезавантаження' -Color Yellow
    pause
}
#endregion
