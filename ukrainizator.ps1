# Ukrainizator v5.0.4
# ============================================================
# Windows Ukrainian language setup script (Modern UI)
# ============================================================

param(
    [switch]$Silent,
    [ValidateSet('All', 'Current')]
    [string]$Mode = 'All',
    [switch]$NoRebootPrompt,
    [switch]$Force,           # Пропустити швидку перевірку "вже налаштовано" і виконати все заново
    [switch]$Revert,          # Відкотити налаштування з останнього резервного знімку
    [switch]$WhatIf,          # Показати, що БУЛО Б зроблено, нічого не змінюючи
    [string[]]$ComputerName,  # Список віддалених машин для запуску (замість локального виконання)
    [System.Management.Automation.PSCredential]$Credential
)

# --- Віддалене розгортання на список машин (якщо вказано -ComputerName) ---
# Локальна машина в цьому режимі нічого сама не змінює - лише копіює скрипт
# на кожну віддалену машину і запускає його там через PS Remoting.
if ($ComputerName -and $ComputerName.Count -gt 0) {
    Write-Host ''
    Write-Host "  Віддалений запуск Українізатора на $($ComputerName.Count) машин(і)..." -ForegroundColor Cyan
    try {
        Invoke-Command -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop -ScriptBlock {
            param($ScriptContent, $ModeArg)
            $tempPath = Join-Path $env:TEMP "Ukrainizator_remote_$(Get-Random).ps1"
            Set-Content -Path $tempPath -Value $ScriptContent -Encoding UTF8
            & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $tempPath -Silent -Mode $ModeArg -NoRebootPrompt
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        } -ArgumentList (Get-Content -Path $PSCommandPath -Raw), $Mode
        Write-Host "  Готово. Перевірте лог-файли на кожній машині (у теці скрипта, %TEMP% на віддаленій)." -ForegroundColor Green
    } catch {
        Write-Host "  Помилка віддаленого запуску: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Переконайтесь, що на віддалених машинах увімкнено PS Remoting (Enable-PSRemoting) і є мережевий доступ." -ForegroundColor DarkYellow
    }
    exit 0
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:DebugMode = $false # Set to $true to enable debug messages

#region === Імпорт модулів та завантаження локалізації ===
# Уся допоміжна логіка (UI, звук, локалізація, бекапи, системні операції)
# живе в окремих .psm1 модулях у папці modules/. Імпортуємо з -Global,
# щоб функції модулів бачили одна одну та глобальний стан скрипта.
$modulesRoot = Join-Path $PSScriptRoot 'modules'
foreach ($moduleName in @('Localization', 'Sound', 'UI', 'BackupRestore', 'SystemSetup', 'Menu', 'Preflight', 'AppsLocalization')) {
    Import-Module (Join-Path $modulesRoot "$moduleName.psm1") -Force -Global -ErrorAction Stop
}
$scriptLocalePath = Join-Path $PSScriptRoot 'locales'
Initialize-Localization -LocalePath $scriptLocalePath
if (-not (Read-LocalizationFile $global:CurrentLanguage)) {
    $global:CurrentLanguage = 'en-US'
    if (-not (Read-LocalizationFile $global:CurrentLanguage)) {
        Write-Host "Fatal Error: Could not load any localization files from $scriptLocalePath. Exiting." -ForegroundColor Red
        exit 1
    }
}
#endregion

#region === Синхронізація WhatIfPreference ===
# Скрипт оголошує власний [switch]$WhatIf, тому стандартна змінна
# $WhatIfPreference НЕ застосовується до нього автоматично. Якщо користувач
# увімкнув dry-run глобально ($WhatIfPreference = $true) або передав -WhatIf:1
# через $PSBoundParameters - приводимо внутрішній прапорець до того ж стану,
# щоб dry-run проходив повністю без інтерактивних зупинок.
if (-not $PSBoundParameters.ContainsKey('WhatIf') -and $WhatIfPreference) {
    $WhatIf = $true
}
# Прапорець "dry-run або тихий режим": усе інтерактивне (підтвердження,
# меню вибору) в цьому режимі пропускається зі значенням за замовчуванням.
$global:IsNonInteractive = [bool]($Silent -or $WhatIf)
#endregion

Write-DebugLog "Script started."

#region === Перевірка цілісності скрипта ===
# Справжній Authenticode-підпис вимагає сертифіката (або платного від довіреного
# центру сертифікації, або самопідписаного - але самопідписаний довіряється лише
# тим машинам, куди ви вручну імпортували його у сховище "Trusted Publishers").
# Для одного скрипта на кількох власних машинах простіший і цілком робочий варіант -
# звичайний хеш SHA-256: поруч зі скриптом лежить файл ukrainizator.ps1.sha256
# з очікуваним хешем; якщо вміст скрипта хоч трохи змінили (пошкодження при
# копіюванні, чиєсь втручання) - хеш не збіжиться і скрипт попередить про це.
function Test-ScriptIntegrity {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath -or -not (Test-Path $scriptPath)) { return $true }
    $hashFile = "$scriptPath.sha256"
    if (-not (Test-Path $hashFile)) {
        Write-DebugLog "Файл контрольної суми не знайдено ($hashFile) - перевірка цілісності пропущена."
        return $true
    }
    try {
        $expected = (Get-Content -Path $hashFile -Raw).Trim().ToUpper()
        $actual = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash.ToUpper()
        if ($expected -ne $actual) {
            Write-Host ''
            Write-Host '  ============================================' -ForegroundColor Red
            Write-Host '  УВАГА: контрольна сума скрипта НЕ збігається!' -ForegroundColor Red
            Write-Host '  Файл могли пошкодити або змінити після підпису.' -ForegroundColor Red
            Write-Host "  Очікувано: $expected" -ForegroundColor DarkGray
            Write-Host "  Отримано:  $actual" -ForegroundColor DarkGray
            Write-Host '  ============================================' -ForegroundColor Red
            $ans = Read-Host '  Продовжити виконання попри це? (y/N)'
            if ($ans -notin @('y', 'Y', 'yes', 'Yes')) {
                Write-Host '  Виконання зупинено користувачем.' -ForegroundColor Yellow
                exit 1
            }
        }
    } catch {
        Write-DebugLog "Не вдалося перевірити цілісність: $($_.Exception.Message)"
    }
    return $true
}

# Щоб (пере)згенерувати файл контрольної суми після легітимного редагування
# скрипта, виконайте окремо в PowerShell:
#   (Get-FileHash -Path .\ukrainizator.ps1 -Algorithm SHA256).Hash | Set-Content .\ukrainizator.ps1.sha256
Test-ScriptIntegrity | Out-Null
#endregion

#region === Захист від паралельного запуску ===
# Named Mutex на рівні ОС (а не файл-замок): якщо скрипт випадково запустили
# двічі (подвійний клік по .bat, або старий інстанс ще не встиг закритись),
# другий запуск одразу побачить, що м'ютекс зайнятий, і ввічливо вийде -
# замість того, щоб два інстанси одночасно лізли в реєстр і калічили
# налаштування один одному.
$global:UkrainizatorMutex = $null
try {
    $createdNew = $false
    $global:UkrainizatorMutex = New-Object System.Threading.Mutex($false, 'Global\UkrainizatorRunning', [ref]$createdNew)
    if (-not $global:UkrainizatorMutex.WaitOne(0)) {
        Invoke-Sound -Type 'Lock'
        Write-Host ''
        Write-Host '  ============================================' -ForegroundColor Red
        Write-Host "  $(Get-LocalizedMessage 'mutex_already_running')" -ForegroundColor Red
        Write-Host "  $(Get-LocalizedMessage 'mutex_danger')" -ForegroundColor Red
        Write-Host "  $(Get-LocalizedMessage 'mutex_close_other')" -ForegroundColor Red
        Write-Host '  ============================================' -ForegroundColor Red
        Write-Host ''
        if (-not $Silent) {
            Write-Host '  Натисніть будь-яку клавішу, щоб завершити...' -ForegroundColor Gray
            $null = [Console]::ReadKey($true)
        }
        exit 1
    }
} catch {
    Write-DebugLog "Не вдалося створити м'ютекс блокування: $($_.Exception.Message)"
}
#endregion

try {
    cmd /c chcp 65001 | Out-Null
} catch {}

try {
    $consolePath = 'HKCU:\Console'
    if (Test-Path $consolePath) {
        # Cascadia Mono - сучасний моношрифт з повним покриттям Unicode
        # (box-drawing, ✓/✗, спінер-символи), присутній за замовчуванням
        # разом із Windows Terminal. Якщо шрифту немає, conhost сам
        # мовчки відкотиться на системний за замовчуванням.
        Set-ItemProperty -Path $consolePath -Name 'FaceName' -Value 'Cascadia Mono' -ErrorAction SilentlyContinue
    }
} catch {}

#region === Settings & State ===
$scriptVersion = '5.0.4'
$global:ScriptVersion = $scriptVersion
$logDir = Join-Path $PSScriptRoot 'log'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
# Не смітимо в корені теки: усі логи йдуть у log/, лишаємо 3 останні (включно з новим).
Get-ChildItem -Path $PSScriptRoot -Filter 'Ukrainizator_*.log' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $logDir -Filter 'Ukrainizator_*.log' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 | Remove-Item -Force -ErrorAction SilentlyContinue
$global:LogFile = Join-Path $logDir "Ukrainizator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$global:BackupDir = Join-Path $PSScriptRoot 'backup'
if (-not (Test-Path $global:BackupDir)) { New-Item -Path $global:BackupDir -ItemType Directory -Force | Out-Null }
# Якщо лишились старі знімки в корені теки (з версій до 5.0.0) - переносимо в backup/
Move-LegacySnapshots -ScriptRoot $PSScriptRoot

$global:StartTime = Get-Date
$global:steps = @()
$global:FailedSteps = New-Object System.Collections.ArrayList   # для "продовжити після помилки" - підсумок наприкінці
$global:BackupData = [ordered]@{}                                # знімок налаштувань "до" - для -Revert

function Test-ShouldRun {
    param([string]$Phase)
    $profile = $global:ActiveProfile
    if (-not $profile -or $profile -eq 'Full') { return $true }
    switch ($Phase) {
        'Language'        { return $profile -in @('Full', 'Language') }
        'Layouts'         { return $profile -in @('Full', 'Layouts') }
        'Derussification' { return $profile -in @('Full', 'Derussification') }
        default           { return $true }
    }
}

function Add-StepIssue {
    param([int]$id, [string]$name, [string]$message)
    [void]$global:FailedSteps.Add([pscustomobject]@{ Id = $id; Name = $name; Message = $message })
}
#endregion

# === Bootstrap ===
Initialize-UI
if ($global:UseAnsi) {
    Set-CursorVisible $false
    Clear-UiScreen
} else {
    try { Clear-Host } catch {}
    Show-PlainHeader
}
Invoke-Sound -Type 'Startup'
try {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { try { [Console]::CursorVisible = $true } catch {} } -ErrorAction SilentlyContinue | Out-Null
} catch {}

#region === Інтерактивне меню ===
if ($PSBoundParameters.Count -eq 0) {
    $global:ActiveProfile = Show-InteractiveMenu
} else {
    $global:ActiveProfile = 'Full'
}

if ($global:ActiveProfile -eq 'Revert') {
    Invoke-RevertMode -WhatIf:$WhatIf
}
if ($global:ActiveProfile -eq 'Exit') {
    Restore-Console
    exit 0
}
if ($global:ActiveProfile -eq 'Apps') {
    Write-Log (Get-LocalizedMessage 'apps_title') -Color Cyan
    Set-AppsUkrainianLocale
    Write-Log (Get-LocalizedMessage 'apps_done') -Color DarkGreen
    Restore-Console
    exit 0
}
#endregion

#region === Відкат (-Revert) ===
if ($Revert) {
    Invoke-RevertMode -WhatIf:$WhatIf
}
#endregion
# Ініціалізація кроків після завантаження мови
$global:steps = @(
    @{ id = 1;  name = (Get-LocalizedMessage 'admin_rights_check');         status = 'pending'; result = ''; details = '' },
    @{ id = 2;  name = (Get-LocalizedMessage 'powershell_version_check');   status = 'pending'; result = ''; details = '' },
    @{ id = 3;  name = (Get-LocalizedMessage 'confirmation');               status = 'pending'; result = ''; details = '' },
    @{ id = 4;  name = (Get-LocalizedMessage 'restore_point');              status = 'pending'; result = ''; details = '' },
    @{ id = 5;  name = (Get-LocalizedMessage 'installation_mode_selection'); status = 'pending'; result = ''; details = '' },
    @{ id = 6;  name = (Get-LocalizedMessage 'modules_check');             status = 'pending'; result = ''; details = '' },
    @{ id = 7;  name = (Get-LocalizedMessage 'language_pack_installation'); status = 'pending'; result = ''; details = '' },
    @{ id = 8;  name = (Get-LocalizedMessage 'interface_language_setting'); status = 'pending'; result = ''; details = '' },
    @{ id = 9;  name = (Get-LocalizedMessage 'regional_formats_setting');   status = 'pending'; result = ''; details = '' },
    @{ id = 10; name = (Get-LocalizedMessage 'derussification_layouts');    status = 'pending'; result = ''; details = '' },
    @{ id = 11; name = (Get-LocalizedMessage 'optimizations_restart');      status = 'pending'; result = ''; details = '' },
    @{ id = 12; name = (Get-LocalizedMessage 'verification_step');        status = 'pending'; result = ''; details = '' }
)

Show-Frame
Write-Log "$(Get-LocalizedMessage 'starting_ukrainizator') v$scriptVersion"
if ($WhatIf) { Write-Log '[WhatIf] Режим попереднього перегляду: жодних реальних змін внесено НЕ буде' -Color DarkYellow }

#region === 0. Швидка перевірка "вже налаштовано" ===
if (-not $Force -and -not $WhatIf) {
    if (Test-AlreadyUkrainized) {
        Set-InfoPanel -Lines @(
            (Get-LocalizedMessage 'quick_check_panel_1'),
            (Get-LocalizedMessage 'quick_check_panel_2')
        )
        Write-Log (Get-LocalizedMessage 'quick_check_already_log') -Color DarkGreen
        if ($Silent) {
            Write-Log (Get-LocalizedMessage 'quick_check_silent_skip') -Color DarkGreen
            Restore-Console
            exit 0
        }
        $again = Show-Prompt -Text (Get-LocalizedMessage 'rerun_full_prompt') -Default 'N'
        if ($again -notin @('Y','y','Yes','YES')) {
            Clear-InfoPanel
            Write-Log (Get-LocalizedMessage 'rerun_declined_log') -Color DarkGreen
            Restore-Console
            exit 0
        }
        Clear-InfoPanel
    }
}
#endregion

#region === Резервний знімок поточних налаштувань (для -Revert) ===
if (-not $WhatIf) {
    Save-SettingsSnapshot | Out-Null
}
#endregion

#region === 1. Privilege Check ===
Set-StepStatus -id 1 -status 'running'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-ErrorExit (Get-LocalizedMessage 'admin_rights_required') 1
}
Set-StepStatus -id 1 -status 'success' -result 'OK'
Write-Log (Get-LocalizedMessage 'admin_rights_confirmed') -Color DarkGreen
#endregion

#region === 2. PowerShell Version ===
Set-StepStatus -id 2 -status 'running'
Show-ProgressBar -Percent 10 -Label (Get-LocalizedMessage 'powershell_version_check')
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-ErrorExit (Get-LocalizedMessage 'powershell_version_required') 2
}
Set-StepStatus -id 2 -status 'success' -result "v$($PSVersionTable.PSVersion)"
Write-Log "$(Get-LocalizedMessage 'powershell_version_detected') $($PSVersionTable.PSVersion)" -Color DarkGreen

# Визначення збірки/редакції Windows - потрібно, щоб коректно обрати спосіб
# встановлення мовного пакету нижче (див. крок 6/7): новий Install-Language
# є не в кожній збірці, тому маємо надійний запасний варіант через DISM.
try {
    $osInfo = Get-WindowsVersionInfo
    $global:WinBuild = $osInfo.Build
    $global:WinDisplayVersion = $osInfo.DisplayVersion
    $global:WinProductName = $osInfo.ProductName
    # Явне форматування через оператор -f: плейсхолдери {0}/{1}/{2} зі словника
    # локалізації підставляються тут, а не залишаються сирим рядком у логі.
    $detectedText = (Get-LocalizedMessage 'detected_system') -f $global:WinProductName, $global:WinDisplayVersion, $global:WinBuild
    Write-Log $detectedText -Color DarkGreen

# Необов'язкова перевірка нової версії - В ІЗОЛЬОВАНОМУ блоці try-catch,
# щоб збій мережі/API ніяк не впливав на зчитування даних ОС вище.
# Ненав'язливо: короткий таймаут, без падіння скрипта, якщо немає інтернету.
try {
    $releaseInfo = Invoke-RestMethod -Uri 'https://api.github.com/repos/sansej8989/Ukrainizator/releases/latest' `
        -Headers @{ 'User-Agent' = 'Ukrainizator' } -TimeoutSec 3 -ErrorAction Stop
    $latestVersion = $releaseInfo.tag_name -replace '^v', ''
    if ($latestVersion -and ([version]$latestVersion -gt [version]$scriptVersion)) {
        Write-Log (Get-LocalizedMessage 'newer_version_available' $latestVersion $scriptVersion 'https://github.com/sansej8989/Ukrainizator/releases/latest') -Color DarkYellow
    }
} catch {
    Write-DebugLog "Перевірка нової версії пропущена: $($_.Exception.Message)"
}
} catch {
    $global:WinBuild = 0
    $global:WinDisplayVersion = 'невідомо'
    $global:WinProductName = 'невідома збірка Windows'
    Write-Log (Get-LocalizedMessage 'os_detect_failed') -Color DarkYellow
}
#endregion

#region === Pre-flight Checks ===
if (-not $Silent -and -not $WhatIf) {
    Test-SystemReadiness | Out-Null
}
#endregion

#region === 3. Warning & Confirmation ===
Set-StepStatus -id 3 -status 'running'
Show-ProgressBar -Percent 30 -Label (Get-LocalizedMessage 'warning')
Set-InfoPanel -Style 'Warning' -Lines @(
    (Get-LocalizedMessage 'warning_message_1'),
    (Get-LocalizedMessage 'warning_message_2'),
    (Get-LocalizedMessage 'warning_message_3')
)
if ($Silent -or $WhatIf) {
    if ($WhatIf) {
        # Dry-run: підтвердження пропускаємо автоматично, нічого не питаємо.
        Set-StepStatus -id 3 -status 'skipped' -result '[WhatIf]'
        Write-Log (Get-LocalizedMessage 'whatif_confirmation_skipped') -Color DarkYellow
    } else {
        Set-StepStatus -id 3 -status 'success' -result 'Auto'
        Write-Log (Get-LocalizedMessage 'confirmation_skipped_silent') -Color DarkGreen
    }
} else {
    $confirm = Show-Prompt -Text (Get-LocalizedMessage 'continue_prompt') -Default 'Y'
    if ($confirm -notin @('Y','y','Yes','YES','ok','OK','yep')) {
        Write-ErrorExit (Get-LocalizedMessage 'cancelled_by_user') 3
    }
    Set-StepStatus -id 3 -status 'success' -result (Get-LocalizedMessage 'confirmed')
    Write-Log (Get-LocalizedMessage 'user_confirmed_execution') -Color DarkGreen
}
Clear-InfoPanel
#endregion

#region === 4. Restore Point ===
Set-StepStatus -id 4 -status 'running'
Show-ProgressBar -Percent 30 -Label (Get-LocalizedMessage 'restore_point')
if ($WhatIf) {
    Set-StepStatus -id 4 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б створено точку відновлення' -Color DarkYellow
} else {
Write-Log (Get-LocalizedMessage 'restore_point_creation')
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description "Before running Ukrainizator" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
    Set-StepStatus -id 4 -status 'success' -result (Get-LocalizedMessage 'created')
    Write-Log (Get-LocalizedMessage 'restore_point_created') -Color DarkGreen
} catch {
    if ($_.Exception.Message -match "24") {
        Set-StepStatus -id 4 -status 'success' -result (Get-LocalizedMessage 'already_created_short')
        Write-Log (Get-LocalizedMessage 'restore_point_already_created') -Color DarkGreen
    } else {
        Set-StepStatus -id 4 -status 'skipped' -result (Get-LocalizedMessage 'skipped')
        Add-StepIssue -id 4 -name (Get-LocalizedMessage 'restore_point') -message (Get-FriendlyErrorMessage $_.Exception.Message)
        Write-Log "$(Get-LocalizedMessage 'restore_point_failed')$(Get-FriendlyErrorMessage $_.Exception.Message)" -Color DarkYellow
    }
}
}
#endregion

#region === 5. Installation Mode Selection ===
Set-StepStatus -id 5 -status 'running'
Show-ProgressBar -Percent 40 -Label (Get-LocalizedMessage 'installation_mode_selection')
if ($Silent -or $WhatIf) {
    # Dry-run (-WhatIf) або тихий режим: меню [A]/[C] пропускаємо і беремо
    # значення за замовчуванням "всі користувачі" (A), щоб dry-run проходив
    # повністю без інтерактивних зупинок.
    $installMode = if ($Silent) { $Mode } else { 'All' }
    $modeText = if ($installMode -eq 'All') { (Get-LocalizedMessage 'all_users_auto') } else { (Get-LocalizedMessage 'current_user_auto') }
    if ($WhatIf) {
        Set-StepStatus -id 5 -status 'skipped' -result "[WhatIf] $modeText"
        Write-Log "[WhatIf] $(Get-LocalizedMessage 'selected_mode') $modeText" -Color DarkYellow
    } else {
        Set-StepStatus -id 5 -status 'success' -result $modeText
        Write-Log "$(Get-LocalizedMessage 'silent_mode_selected') $modeText" -Color DarkGreen
    }
} else {
    Set-InfoPanel -Lines @(
        (Get-LocalizedMessage 'apply_to'),
        "  $(Get-LocalizedMessage 'all_users_recommended')",
        "  $(Get-LocalizedMessage 'current_user_only')"
    )
    $installMode = Show-Prompt -Text (Get-LocalizedMessage 'your_choice') -Default 'A'
    if ($installMode -notin @('A','a','All','ALL')) {
        $installMode = 'Current'
        $modeText = (Get-LocalizedMessage 'current_user')
    } else {
        $installMode = 'All'
        $modeText = (Get-LocalizedMessage 'all_users')
    }
    Set-StepStatus -id 5 -status 'success' -result $modeText
    Write-Log "$(Get-LocalizedMessage 'selected_mode') $modeText" -Color DarkGreen
    Clear-InfoPanel
}
#endregion

#region === 6. Modules ===
Set-StepStatus -id 6 -status 'running'
Show-ProgressBar -Percent 50 -Label (Get-LocalizedMessage 'modules_check')
Import-Module LanguagePackManagement -ErrorAction SilentlyContinue
$global:UseModernLanguageApi = [bool](Get-Command Install-Language -ErrorAction SilentlyContinue)
if ($global:UseModernLanguageApi) {
    Set-StepStatus -id 6 -status 'success' -result (Get-LocalizedMessage 'loaded')
    Write-Log (Get-LocalizedMessage 'languagemanagement_loaded') -Color DarkGreen
} else {
    # Модуль LanguagePackManagement є не в кожній збірці Windows (з'явився
    # пізніше і не завжди присутній навіть у сучасних Windows 10/11).
    # DISM-командлети Add-/Get-WindowsCapability є набагато старішими й
    # практично гарантовано доступні на будь-якій підтримуваній збірці -
    # тому крок не провалюється, а просто переходить на них.
    if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
        Set-StepStatus -id 6 -status 'skipped' -result (Get-LocalizedMessage 'fallback_dism')
        Write-Log (Get-LocalizedMessage 'dism_fallback_log') -Color DarkYellow
    } else {
        Set-StepStatus -id 6 -status 'skipped' -result (Get-LocalizedMessage 'languagemanagement_not_available')
        Add-StepIssue -id 6 -name (Get-LocalizedMessage 'modules_check') -message (Get-LocalizedMessage 'langpack_no_way')
        Write-Log (Get-LocalizedMessage 'languagemanagement_not_available') -Color DarkYellow
    }
}
#endregion

if (Test-ShouldRun 'Language') {
#region === 7. Language Pack ===
Set-StepStatus -id 7 -status 'running'
Show-ProgressBar -Percent 60 -Label (Get-LocalizedMessage 'language_pack_installation')
$targetLanguageTag = 'uk-UA'
$targetLanguageInstalled = $false

function Test-UkrainianLanguageInstalled {
    if (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue) {
        if ((Get-InstalledLanguage | Out-String) -match $targetLanguageTag) { return $true }
    }
    if ((Get-WinUserLanguageList | Out-String) -match $targetLanguageTag) { return $true }
    if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
        $cap = Get-WindowsCapability -Online -Name "Language.Basic~~~$targetLanguageTag~0.0.1.0" -ErrorAction SilentlyContinue
        if ($cap -and $cap.State -eq 'Installed') { return $true }
    }
    return $false
}

$targetLanguageInstalled = Test-UkrainianLanguageInstalled

if ($targetLanguageInstalled) {
    Set-StepStatus -id 7 -status 'skipped' -result (Get-LocalizedMessage 'already_installed')
    Write-Log (Get-LocalizedMessage 'language_already_installed' $targetLanguageTag) -Color DarkYellow
} elseif ($WhatIf) {
    Set-StepStatus -id 7 -status 'skipped' -result '[WhatIf] Буде встановлено'
    Write-Log "[WhatIf] Було б встановлено мовний пакет $targetLanguageTag" -Color DarkYellow
} elseif (-not $global:UseModernLanguageApi -and -not (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
    Set-StepStatus -id 7 -status 'skipped' -result (Get-LocalizedMessage 'langpack_no_way_short')
    Add-StepIssue -id 7 -name (Get-LocalizedMessage 'language_pack_installation') -message (Get-LocalizedMessage 'langpack_no_way')
    Write-Log (Get-LocalizedMessage 'langpack_skipped_log') -Color DarkYellow
} else {
    Write-Log (Get-LocalizedMessage 'installing_language' $targetLanguageTag) -Color DarkYellow
    try {
        Install-UkrainianLanguagePack -LanguageTag $targetLanguageTag -UseModernApi:$global:UseModernLanguageApi
        $targetLanguageInstalled = $false
        for ($i = 1; $i -le 15; $i++) {
            Start-Sleep -Seconds 3
            $global:UIState.SpinnerFrame++
            if ($global:UseAnsi) { Show-Frame }
            if (Test-UkrainianLanguageInstalled) { $targetLanguageInstalled = $true; break }
        }
        if (-not $targetLanguageInstalled) {
            Set-StepStatus -id 7 -status 'skipped' -result (Get-LocalizedMessage 'status_error')
            Add-StepIssue -id 7 -name (Get-LocalizedMessage 'language_pack_installation') -message (Get-LocalizedMessage 'language_not_found_after_install' $targetLanguageTag)
            Write-Log (Get-LocalizedMessage 'language_not_found_after_install' $targetLanguageTag) -Color DarkYellow
        } else {
            Set-StepStatus -id 7 -status 'success' -result (Get-LocalizedMessage 'installed')
            Write-Log (Get-LocalizedMessage 'language_installed_successfully' $targetLanguageTag) -Color DarkGreen
        }
    } catch {
        Set-StepStatus -id 7 -status 'skipped' -result (Get-LocalizedMessage 'status_error')
        Add-StepIssue -id 7 -name (Get-LocalizedMessage 'language_pack_installation') -message (Get-FriendlyErrorMessage $_.Exception.Message)
        Write-Log (Get-LocalizedMessage 'installation_error' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
    }
}
#endregion
}
#endregion

if (Test-ShouldRun 'Language') {
#region === 8. Interface ===
Set-StepStatus -id 8 -status 'running'
Show-ProgressBar -Percent 70 -Label (Get-LocalizedMessage 'interface_label')
if ($WhatIf) {
    Set-StepStatus -id 8 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б встановлено мову інтерфейсу uk-UA' -Color DarkYellow
} else {
try {
    Set-WinUILanguageOverride -Language 'uk-UA' -ErrorAction Stop -WarningAction SilentlyContinue
    $langCode = '0422'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value $langCode -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value $langCode -ErrorAction Stop

    if ($installMode -eq 'All') {
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Log (Get-LocalizedMessage 'copied_settings_welcome_new_user') -Color DarkGreen
        } catch {
            Write-Log (Get-LocalizedMessage 'copying_settings_failed_win10') -Color DarkYellow
        }
    }
    Set-StepStatus -id 8 -status 'success' -result (Get-LocalizedMessage 'interface_language_set_result' 'uk-UA')
    Write-Log (Get-LocalizedMessage 'interface_language_set' 'uk-UA') -Color DarkGreen
} catch {
    Set-StepStatus -id 8 -status 'skipped' -result (Get-LocalizedMessage 'status_partial')
    Add-StepIssue -id 8 -name (Get-LocalizedMessage 'interface_language_setting') -message (Get-FriendlyErrorMessage $_.Exception.Message)
    Write-Log (Get-LocalizedMessage 'interface_language_error' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
}
}
#endregion
}
#endregion

if (Test-ShouldRun 'Language') {
#region === 9. Regional Formats ===
Set-StepStatus -id 9 -status 'running'
Show-ProgressBar -Percent 80 -Label (Get-LocalizedMessage 'regional_formats_label')
if ($WhatIf) {
    Set-StepStatus -id 9 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б встановлено регіон uk-UA, часовий пояс, понеділок як перший день тижня' -Color DarkYellow
} else {
try {
    Set-Culture -CultureInfo 'uk-UA' -ErrorAction Stop -WarningAction SilentlyContinue
    Set-WinSystemLocale -SystemLocale 'uk-UA' -ErrorAction Stop -WarningAction SilentlyContinue
    $geoId = 240
    Set-WinHomeLocation -GeoId $geoId -ErrorAction Stop -WarningAction SilentlyContinue

    # Часовий пояс України
    try {
        Set-TimeZone -Id 'FLE Standard Time' -ErrorAction Stop
        Write-Log (Get-LocalizedMessage 'timezone_set') -Color DarkGreen
    } catch {
        Write-Log (Get-LocalizedMessage 'timezone_error' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
    }

    # Перший день тижня - понеділок, символ валюти - гривня (₴), явно в реєстрі,
    # оскільки Set-Culture не завжди повністю оновлює legacy NLS-ключі реєстру.
    try {
        $intlPath = 'HKCU:\Control Panel\International'
        Set-ItemProperty -Path $intlPath -Name 'iFirstDayOfWeek' -Value '0' -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $intlPath -Name 'sCurrency' -Value ([char]0x20B4) -ErrorAction SilentlyContinue
        Write-Log (Get-LocalizedMessage 'first_day_currency_set') -Color DarkGreen
    } catch {}

    Set-StepStatus -id 9 -status 'success' -result (Get-LocalizedMessage 'regional_formats_set_result' 'uk-UA' 'uk-UA')
    Write-Log (Get-LocalizedMessage 'regional_standards_set' 'uk-UA') -Color DarkGreen
} catch {
    Set-StepStatus -id 9 -status 'skipped' -result (Get-LocalizedMessage 'status_partial')
    Add-StepIssue -id 9 -name (Get-LocalizedMessage 'regional_formats_setting') -message (Get-FriendlyErrorMessage $_.Exception.Message)
    Write-Log (Get-LocalizedMessage 'regional_formats_error' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
}
}
#endregion
}
#endregion

#region === 10. Derussification & Layouts ===
Set-StepStatus -id 10 -status 'running'
Show-ProgressBar -Percent 90 -Label (Get-LocalizedMessage 'layouts_label')
if ($WhatIf) {
    Set-StepStatus -id 10 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б налаштовано розкладки та видалено ru-компоненти' -Color DarkYellow
} else {
    $runLayouts = Test-ShouldRun 'Layouts'
    $runDeruss = Test-ShouldRun 'Derussification'

    if ($runLayouts) {
        $layoutOk = Invoke-LayoutConfiguration
        if (-not $layoutOk) {
            Add-StepIssue -id 10 -name (Get-LocalizedMessage 'derussification_layouts') -message (Get-LocalizedMessage 'layout_cleanup_error')
        }
    }
    if ($runDeruss) {
        Invoke-DeepDerussification
    }

    if ($runLayouts -or $runDeruss) {
        Set-StepStatus -id 10 -status 'success' -result (Get-LocalizedMessage 'layouts_set_result' @('uk-UA', 'en-US'))
        Write-Log (Get-LocalizedMessage 'layout_cleanup_completed' @('uk-UA', 'en-US')) -Color DarkGreen
    }
}
#endregion

#region === 11. Optimizations & Explorer Restart ===
Set-StepStatus -id 11 -status 'running'
Show-ProgressBar -Percent 95 -Label (Get-LocalizedMessage 'optimization_label')
if ($WhatIf) {
    Set-StepStatus -id 11 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б застосовано оптимізації та перезапущено провідник' -Color DarkYellow
} else {
$optSuccess = Invoke-Optimizations

if ($optSuccess) {
    Set-StepStatus -id 11 -status 'success' -result (Get-LocalizedMessage 'status_applied_restart')
    Write-Log (Get-LocalizedMessage 'optimizations_completed') -Color DarkGreen
} else {
    Set-StepStatus -id 11 -status 'skipped' -result (Get-LocalizedMessage 'status_partial')
    Add-StepIssue -id 11 -name (Get-LocalizedMessage 'optimizations_restart') -message (Get-LocalizedMessage 'optimizations_partial')
    Write-Log (Get-LocalizedMessage 'some_optimizations_not_applied') -Color DarkYellow
}
}
#endregion

#region === 12. Перевірка результату (верифікація) ===
Set-StepStatus -id 12 -status 'running'
Show-ProgressBar -Percent 98 -Label 'Перевірка результату'
if ($WhatIf) {
    Set-StepStatus -id 12 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Перевірку результату пропущено (змін не було)' -Color DarkYellow
} else {
    try {
        $checks = Get-VerificationChecks
        $markWarn = Get-LocalizedMessage 'warning'
        foreach ($c in $checks) {
            $mark = if ($c.Ok) { 'OK' } else { $markWarn }
            $color = if ($c.Ok) { 'DarkGreen' } else { 'DarkYellow' }
            Write-Log "  [$mark] $($c.Name): $($c.Detail)" -Color $color
        }
        $passCount = ($checks | Where-Object { $_.Ok }).Count
        $totalCount = $checks.Count
        if ($passCount -eq $totalCount) {
            Set-StepStatus -id 12 -status 'success' -result "$passCount/$totalCount OK"
        } else {
            Set-StepStatus -id 12 -status 'skipped' -result "$passCount/$totalCount OK"
            Add-StepIssue -id 12 -name (Get-LocalizedMessage 'verification_step') -message (Get-LocalizedMessage 'checks_not_all_passed' $passCount $totalCount)
        }
} catch {
    Set-StepStatus -id 12 -status 'skipped' -result (Get-LocalizedMessage 'status_error')
    Write-Log (Get-LocalizedMessage 'verify_failed_log' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
}
}#endregion

# === Completion ===
try {
    if ($global:UkrainizatorMutex) {
        $global:UkrainizatorMutex.ReleaseMutex()
        $global:UkrainizatorMutex.Dispose()
    }
} catch {}

Show-ProgressBar -Percent 100 -Label (Get-LocalizedMessage 'all_done')

try {
    Invoke-Sound -Type 'Fanfare'
} catch {}

Clear-InfoPanel
Show-CompletionBanner

if ($global:FailedSteps.Count -gt 0) {
    $issueLines = @((Get-LocalizedMessage 'issues_summary' $global:FailedSteps.Count))
    $issueLines += ($global:FailedSteps | ForEach-Object { "  • $($_.Name): $($_.Message)" })
    Set-InfoPanel -Style 'Warning' -Lines $issueLines
    Write-Host ''
    Start-Sleep -Seconds 3
}

if ($WhatIf) {
    Set-InfoPanel -Lines @(
        (Get-LocalizedMessage 'whatif_no_changes_1'),
        (Get-LocalizedMessage 'whatif_no_changes_2')
    )
    Write-Log (Get-LocalizedMessage 'whatif_done_log') -Color DarkYellow
    Restore-Console
    Write-Host ''
    Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
} elseif ($NoRebootPrompt) {
    Write-Log (Get-LocalizedMessage 'auto_reboot_prompt') -Color DarkGreen
    $proceed = Show-CountdownReboot -Seconds 5
    if ($proceed) {
        Restore-Console
        Restart-Computer
    } else {
        Set-InfoPanel -Style 'Warning' -Lines @(
            (Get-LocalizedMessage 'reboot_cancelled_panel'),
            (Get-LocalizedMessage 'dont_forget_reboot')
        )
        Write-Log (Get-LocalizedMessage 'auto_reboot_cancelled_log') -Color DarkYellow
        Restore-Console
    }
} else {
    $reboot = Show-Prompt -Text (Get-LocalizedMessage 'reboot_now_prompt') -Default 'Y'
    if ($reboot -in (Get-LocalizedMessage 'reboot_yes_answers')) {
        Write-Log (Get-LocalizedMessage 'reboot_requested') -Color DarkGreen
        $proceed = Show-CountdownReboot -Seconds 15
        if ($proceed) {
            Restore-Console
            Restart-Computer
        } else {
            Set-InfoPanel -Style 'Warning' -Lines @(
                (Get-LocalizedMessage 'reboot_cancelled_panel'),
                (Get-LocalizedMessage 'dont_forget_reboot')
            )
            Write-Log (Get-LocalizedMessage 'reboot_cancelled_countdown_log') -Color DarkYellow
            Restore-Console
            Write-Host ''
            Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
            $null = [Console]::ReadKey($true)
        }
    } else {
        Set-InfoPanel -Style 'Warning' -Lines @(
            (Get-LocalizedMessage 'dont_forget_reboot'),
            (Get-LocalizedMessage 'thank_you')
        )
        Write-Log (Get-LocalizedMessage 'user_declined_reboot') -Color DarkYellow
        Restore-Console
        Write-Host ''
        Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    }
}
