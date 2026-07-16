# Ukrainizator v3.3.0
# ============================================================
# Встановлення української мови для Windows (Professional UI)
# ============================================================

# Встановлення UTF-8 та підтримки кирилиці
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Примусове перемикання кодової сторінки консолі на UTF-8 (65001)
try {
    cmd /c chcp 65001 | Out-Null
} catch {}

# Налаштування шрифту консолі через реєстр для підтримки кирилиці та розміру
try {
    $consolePath = 'HKCU:\Console'
    if (Test-Path $consolePath) {
        Set-ItemProperty -Path $consolePath -Name 'FaceName' -Value 'Lucida Console' -ErrorAction SilentlyContinue
        # Встановлення розміру шрифту 16pt (0x100000)
        Set-ItemProperty -Path $consolePath -Name 'FontSize' -Value 0x100000 -ErrorAction SilentlyContinue
    }
} catch {}

#region === Settings & State ===
$scriptVersion = '3.3.0'
Get-ChildItem -Path $PSScriptRoot -Filter 'Ukrainizator_*.log' -File | Remove-Item -Force
$logFile = Join-Path $PSScriptRoot "Ukrainizator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$startTime = Get-Date

# Визначення кроків
$global:steps = @(
    @{ id = 1;  name = 'Права адміністратора';   status = 'pending'; result = '' },
    @{ id = 2;  name = 'Версія PowerShell';      status = 'pending'; result = '' },
    @{ id = 3;  name = 'Перевірка інтернету';   status = 'pending'; result = '' },
    @{ id = 4;  name = 'Підтвердження дій';    status = 'pending'; result = '' },
    @{ id = 5;  name = 'Режим встановлення';      status = 'pending'; result = '' },
    @{ id = 6;  name = 'Системні модулі';        status = 'pending'; result = '' },
    @{ id = 7;  name = 'Мовний пакет uk-UA';     status = 'pending'; result = '' },
    @{ id = 8;  name = 'Мова інтерфейсу';        status = 'pending'; result = '' },
    @{ id = 9;  name = 'Розкладки клавіатури';  status = 'pending'; result = '' },
    @{ id = 10; name = 'Оптимізація системи';    status = 'pending'; result = '' }
)

$global:uiHeaderHeight = 11
$global:uiListHeight = 12
#endregion

#region === UI Functions ===

function Clear-ActivityZone {
    # Очищення зони під списком та прогрес-баром (приблизно 10 рядків)
    for ($i = 0; $i -lt 12; $i++) {
        [Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + $i)
        Write-Host (' ' * $host.UI.RawUI.WindowSize.Width) -NoNewline
    }
}

function Write-Log {
    param([string]$Message, [string]$Color = 'White')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    
    # Вивід у зону активності (під списком)
    [Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 1)
    Write-Host "  $logMessage" -ForegroundColor $Color
}

function Set-StepStatus {
    param([int]$id, [string]$status, [string]$result = '')
    $step = $global:steps | Where-Object { $_.id -eq $id }
    $step.status = $status
    $step.result = $result
    
    # Звуковий супровід: тональний сигнал, що зростає з кожним кроком
    if ($status -eq 'success' -or $status -eq 'skipped') {
        $freq = 350 + ($id * 50)
        [Console]::Beep($freq, 80)
    }

    Update-UI
}

function Show-ProgressBar {
    param([int]$Percent, [string]$Label = '')
    $barSize = 30
    $filled = [int][math]::Floor($Percent / 100 * $barSize)
    $empty = [int]($barSize - $filled)
    $bar = ([string][char]9608 * $filled) + ([string][char]9617 * $empty)
    
    [Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight)
    # Очищення рядка перед виводом, щоб уникнути залишків старого тексту
    Write-Host (' ' * $host.UI.RawUI.WindowSize.Width) -NoNewline
    [Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight)
    
    if ($Label) { Write-Host "  $bar  $Percent%  $Label" -ForegroundColor Yellow }
    else { Write-Host "  $bar  $Percent%" -ForegroundColor Yellow }
}

function Update-UI {
    [Console]::SetCursorPosition(0, $global:uiHeaderHeight)
    foreach ($step in $global:steps) {
        $marker = ' [ ] '
        $color = 'Gray'
        switch ($step.status) {
            'pending' { $marker = ' [ ] '; $color = 'Gray' }
            'running' { $marker = ' [>>]'; $color = 'Yellow' }
            'success' { $marker = ' [V] '; $color = 'Green' }
            'error'   { $marker = ' [X] '; $color = 'Red' }
            'skipped' { $marker = ' [~] '; $color = 'Cyan' }
        }
        $resText = if ($step.result) { " -> $($step.result)" } else { "" }
        Write-Host "$marker $($step.id). $($step.name)$resText" -ForegroundColor $color
    }
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
    Write-Host "  UKRAINIZATOR  v$scriptVersion" -ForegroundColor Yellow
    Write-Host '  Встановлення української мови в Windows' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "Лог: $logFile" -ForegroundColor Gray
    Write-Host ''
}

function Write-ErrorExit {
    param([string]$Message, [int]$stepId)
    Set-StepStatus -id $stepId -status 'error' -result 'Помилка'
    [console]::beep(300,300)
    Clear-ActivityZone
    Write-Host ''
    Write-Host "  [!] $Message" -ForegroundColor Red
    Write-Log "ERROR: $Message" -Color Red
    Write-Host ''
    Write-Host 'Натисніть будь-яку клавішу для виходу...' -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    exit 1
}

function Read-HostWithDefault {
    param(
        [string]$Default = 'Y'
    )
    try {
        Write-Host $Default -NoNewline
        
        $inputBuffer = New-Object System.Text.StringBuilder
        $inputBuffer.Append($Default) | Out-Null
        
        while ($true) {
            $keyInfo = [Console]::ReadKey($true)
            if ($keyInfo.Key -eq [ConsoleKey]::Enter) {
                Write-Host ''
                return $inputBuffer.ToString()
            }
            elseif ($keyInfo.Key -eq [ConsoleKey]::Backspace) {
                if ($inputBuffer.Length -gt 0) {
                    $inputBuffer.Remove($inputBuffer.Length - 1, 1) | Out-Null
                    [Console]::SetCursorPosition([Console]::CursorLeft - 1, [Console]::CursorTop)
                    Write-Host ' ' -NoNewline
                    [Console]::SetCursorPosition([Console]::CursorLeft - 1, [Console]::CursorTop)
                }
            }
            else {
                $char = $keyInfo.KeyChar
                if ($char) {
                    $inputBuffer.Append($char) | Out-Null
                    Write-Host $char -NoNewline
                }
            }
        }
    } catch {
        $result = Read-Host
        if ([string]::IsNullOrWhiteSpace($result)) {
            return $Default
        }
        return $result
    }
}
#endregion

# === Start ===
Show-FlagHeader
Update-UI
Write-Log "Запуск Ukrainizator v$scriptVersion"

#region === 1. Privilege Check ===
Set-StepStatus -id 1 -status 'running'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-ErrorExit 'Потрібні права адміністратора!' 1
}
Set-StepStatus -id 1 -status 'success' -result 'OK'
Write-Log 'Права адміністратора підтверджено' -Color Green
#endregion

#region === 2. PowerShell Version ===
Set-StepStatus -id 2 -status 'running'
Show-ProgressBar -Percent 10 -Label 'Перевірка PS'
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-ErrorExit "Потрібен PowerShell 5.1+" 2
}
Set-StepStatus -id 2 -status 'success' -result "v$($PSVersionTable.PSVersion)"
Write-Log "Версія PowerShell: $($PSVersionTable.PSVersion)" -Color Green
#endregion

#region === 3. Internet ===
Set-StepStatus -id 3 -status 'running'
Show-ProgressBar -Percent 20 -Label 'Мережа'
Write-Log 'Перевірка підключення...'
$online = $false
try {
    $online = Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet -ErrorAction Stop
} catch {
    try { Invoke-WebRequest -Uri 'https://www.microsoft.com' -UseBasicParsing -ErrorAction Stop | Out-Null; $online = $true } catch {}
}
if (-not $online) {
    Write-ErrorExit "Інтернет недоступний!" 3
}
Set-StepStatus -id 3 -status 'success' -result 'Online'
Write-Log 'Інтернет доступний' -Color Green
#endregion

#region === 4. Warning ===
Set-StepStatus -id 4 -status 'running'
Show-ProgressBar -Percent 30 -Label 'Увага'
Clear-ActivityZone
[Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 2)
Write-Host '  УВАГА: Скрипт змінює системну мову та розкладки.' -ForegroundColor Red
Write-Host '  Після завершення потрібне перезавантаження.' -ForegroundColor Red
Write-Host '  РЕКОМЕНДУЄМО СТВОРИТИ ТОЧКУ ВІДНОВЛЕННЯ.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Продовжити? (Y/N): ' -NoNewline -ForegroundColor Yellow
$confirm = Read-HostWithDefault -Default 'Y'
if ($confirm -notin @('Y','y','Yes','YES','ok','OK','yep')) {
    Set-StepStatus -id 4 -status 'error' -result 'Скасовано'
    Write-Log 'Скасовано користувачем' -Color Red
    exit 1
}
Set-StepStatus -id 4 -status 'success' -result 'Підтверджено'
Write-Log 'Користувач підтвердив виконання' -Color Green
#endregion

#region === 5. Installation Mode Selection ===
Set-StepStatus -id 5 -status 'running'
Show-ProgressBar -Percent 40 -Label 'Режим'
Clear-ActivityZone
[Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 2)
Write-Host '  Застосувати до:' -ForegroundColor Yellow
Write-Host '    [A] всіх користувачів (рекомендовано)' -ForegroundColor Cyan
Write-Host '    [C] тільки поточного користувача' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Ваш вибір (A/C): ' -NoNewline -ForegroundColor Yellow
$installMode = Read-HostWithDefault -Default 'A'
if ($installMode -notin @('A','a','All','ALL')) {
    $installMode = 'Current'
    $modeText = 'Поточний користувач'
} else {
    $installMode = 'All'
    $modeText = 'Всі користувачі'
}
Set-StepStatus -id 5 -status 'success' -result $modeText
Write-Log "Вибрано режим: $modeText" -Color Green
#endregion

#region === 6. Modules ===
Set-StepStatus -id 6 -status 'running'
Show-ProgressBar -Percent 50 -Label 'Модулі'
Import-Module LanguagePackManagement -ErrorAction SilentlyContinue
if (-not (Get-Module -ListAvailable -Name LanguagePackManagement)) {
    Write-ErrorExit 'Модуль LanguagePackManagement недоступний.' 6
}
Set-StepStatus -id 6 -status 'success' -result 'Завантажено'
Write-Log 'Модуль LanguagePackManagement завантажено' -Color Green
#endregion

#region === 7. Language Pack ===
Set-StepStatus -id 7 -status 'running'
Show-ProgressBar -Percent 60 -Label 'Мовний пакет'
$ukUaInstalled = $false
if ((Get-InstalledLanguage | Out-String) -match 'uk-UA') { $ukUaInstalled = $true }
if (-not $ukUaInstalled) { if ((Get-WinUserLanguageList | Out-String) -match 'uk-UA') { $ukUaInstalled = $true } }

if ($ukUaInstalled) {
    Set-StepStatus -id 7 -status 'skipped' -result 'Вже встановлено'
    Write-Log 'uk-UA вже встановлено, пропускаємо' -Color Yellow
} else {
    Write-Log 'Встановлення uk-UA... (це може зайняти час)' -Color Yellow
    try {
        Install-Language -Language 'uk-UA' -CopyToSettings -ExcludeFeatures -ErrorAction Stop
        $ukUaInstalled = $false
        for ($i = 1; $i -le 15; $i++) {
            Start-Sleep -Seconds 3
            if ((Get-InstalledLanguage | Out-String) -match 'uk-UA') { $ukUaInstalled = $true; break }
            if ((Get-WinUserLanguageList | Out-String) -match 'uk-UA') { $ukUaInstalled = $true; break }
        }
        if (-not $ukUaInstalled) { Write-ErrorExit 'uk-UA не знайдено після встановлення.' 7 }
        Set-StepStatus -id 7 -status 'success' -result 'Встановлено'
        Write-Log 'uk-UA встановлено успішно' -Color Green
    } catch { Write-ErrorExit "Помилка встановлення: $($_.Exception.Message)" 7 }
}
#endregion

#region === 8. Interface ===
Set-StepStatus -id 8 -status 'running'
Show-ProgressBar -Percent 75 -Label 'Інтерфейс'
try {
    Set-WinUILanguageOverride -Language 'uk-UA' -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value '0422' -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value '0422' -ErrorAction Stop
    
    if ($installMode -eq 'All') {
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $True -NewUser $True -ErrorAction Stop
            Write-Log 'Скопійовано: WelcomeScreen+NewUser' -Color Green
        } catch {
            Write-Log "Копіювання налаштувань не вдалося (Win10)" -Color Yellow
        }
    }
    Set-StepStatus -id 8 -status 'success' -result 'uk-UA встановлено'
    Write-Log 'Мова інтерфейсу встановлена' -Color Green
} catch {
    Set-StepStatus -id 8 -status 'skipped' -result 'Частково'
    Write-Log "Мова інтерфейсу: $($_.Exception.Message)" -Color Yellow
}
#endregion

#region === 9. Layouts ===
Set-StepStatus -id 9 -status 'running'
Show-ProgressBar -Percent 85 -Label 'Розкладки'
try {
    # Виправлення: створення списку з однією мовою, потім додавання іншої
    $ll = New-WinUserLanguageList -Language 'uk-UA'
    $ll.Add('en-US')
    
    $uk = $ll | Where-Object { $_.LanguageTag -eq 'uk-UA' }
    $uk.InputMethodTips.Clear(); $uk.InputMethodTips.Add('0422:00000422')
    $en = $ll | Where-Object { $_.LanguageTag -eq 'en-US' }
    $en.InputMethodTips.Clear(); $en.InputMethodTips.Add('0409:00000409')
    
    Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction Stop
    
    $togglePath = 'HKCU:\Keyboard Layout\Toggle'
    if (-not (Test-Path $togglePath)) { New-Item -Path $togglePath -Force | Out-Null }
    Set-ItemProperty -Path $togglePath -Name 'Hotkey' -Value 1 -ErrorAction Stop
    
    Set-StepStatus -id 9 -status 'success' -result 'UKR+ENG (Shift+Alt)'
    Write-Log 'Розкладки та гарячі клавіші встановлено' -Color Green
} catch {
    Set-StepStatus -id 9 -status 'skipped' -result 'Помилка'
    Write-Log "Помилка Layouts: $($_.Exception.Message)" -Color Yellow
}
#endregion

#region === 10. Optimizations ===
Set-StepStatus -id 10 -status 'running'
Show-ProgressBar -Percent 95 -Label 'Оптимізація'
$optSuccess = $true
try { Set-ItemProperty -Path 'HKU:\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '80000002' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '510' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-WinSystemLocale -SystemLocale 'uk-UA' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-WinHomeLocation -GeoId 240 -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '20' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Sound' -Name 'Beep' -Value 'no' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }

if ($optSuccess) {
    Set-StepStatus -id 10 -status 'success' -result 'Застосовано'
    Write-Log 'Системні оптимізації виконано' -Color Green
} else {
    Set-StepStatus -id 10 -status 'skipped' -result 'Частково'
    Write-Log 'Деякі системні оптимізації не вдалися' -Color Yellow
}
#endregion

# === Completion ===
Show-ProgressBar -Percent 100 -Label 'Готово!'

# Переможна мелодія
[Console]::Beep(523, 150) # C5
[Console]::Beep(659, 150) # E5
[Console]::Beep(784, 150) # G5
[Console]::Beep(1046, 300) # C6

Clear-ActivityZone
[Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 3)
Write-Host '============================================' -ForegroundColor Green
Write-Host '   ВСЕ ГОТОВО!' -ForegroundColor Yellow
Write-Host '============================================' -ForegroundColor Green
$elapsed = (Get-Date) - $startTime
Write-Host "Час: $($elapsed.Minutes)хв $($elapsed.Seconds)сек" -ForegroundColor Gray
Write-Host "Лог: $logFile" -ForegroundColor Gray
Write-Host ''
Write-Host 'Перезавантажити зараз? (Y/N): ' -NoNewline -ForegroundColor Yellow
$reboot = Read-HostWithDefault -Default 'Y'
if ($reboot -in @('Y','y','Yes','YES','ok','OK','yep')) {
    Write-Host '  Перезавантаження... До зустрічі!' -ForegroundColor Green
    Write-Log 'Запитується перезавантаження' -Color Green
    Start-Sleep -Seconds 2
    Restart-Computer
} else {
    Write-Host '  [i] Не забудьте перезавантажити комп''ютер пізніше.' -ForegroundColor Yellow
    Write-Host '  Дякуємо за використання Ukrainizator!' -ForegroundColor Cyan
    Write-Log 'Користувач відмовився від перезавантаження' -Color Yellow
    pause
}
