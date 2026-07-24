# Ukrainizator v5.0.0
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

function Write-DebugLog {
    param(
        [string]$Message,
        [string]$Color = 'DarkGray'
    )
    if ($global:DebugMode) {
        Write-Host "DEBUG: $Message" -ForegroundColor $Color
    }
}

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
        Write-Host ''
        Write-Host '  ============================================' -ForegroundColor Red
        Write-Host '  Українізатор вже запущено в іншому вікні!' -ForegroundColor Red
        Write-Host '  Одночасний запуск двох копій може пошкодити налаштування.' -ForegroundColor Red
        Write-Host '  Закрийте інший запущений екземпляр і спробуйте знову.' -ForegroundColor Red
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

#region === Localization ===
$scriptLocalePath = Join-Path $PSScriptRoot "locales"
$global:CurrentLanguage = 'uk-UA' # За замовчуванням
$global:LocalizedStrings = @{}

function Read-LocalizationFile {
    param([string]$langCode)
    $filePath = Join-Path $scriptLocalePath "$langCode.json"
    Write-DebugLog "Attempting to load localization file: $filePath"
    if (Test-Path $filePath) {
        Write-DebugLog "File exists: $filePath"
        try {
            $rawContent = Get-Content -Raw -Path $filePath -Encoding UTF8
            Write-DebugLog "JSON raw content preview (first 100 chars): $($rawContent.Substring(0, [Math]::Min(100, $rawContent.Length)))"
            $jsonObject = $rawContent | ConvertFrom-Json -ErrorAction Stop
            $global:LocalizedStrings = [System.Collections.Hashtable]::new()
            $jsonObject.PSObject.Properties | ForEach-Object {
                $global:LocalizedStrings[$_.Name] = $_.Value
            }
            Write-DebugLog "Successfully loaded localization for $langCode." -Color DarkGreen
            return $true
        } catch {
            Write-Warning ("Failed to load localization file for {0}: {1}" -f $langCode, $_.Exception.Message)
            return $false
        }
    } else {
        Write-DebugLog "Localization file not found: $filePath"
    }
    return $false
}

function Get-LocalizedMessage {
    param(
        [string]$key,
        [object[]]$MessageArgs
    )
    if ($global:LocalizedStrings.ContainsKey($key)) {
        $message = $global:LocalizedStrings[$key]
        if ($MessageArgs) {
            try {
                return ($message -f $MessageArgs)
            } catch {
                return $message
            }
        }
        return $message
    }
    # Резервний варіант, якщо ключа немає у файлі локалізації: людяніший
    # текст замість сирого ідентифікатора на кшталт "language_already_installed".
    try {
        $pretty = ($key -replace '_', ' ')
        return (Get-Culture).TextInfo.ToTitleCase($pretty)
    } catch {
        return $key
    }
}

function Get-FriendlyErrorMessage {
    # Типові .NET/PowerShell винятки завжди англійською - перекладаємо
    # найпоширеніші причини, а невідомі лишаємо як є (з оригіналом у дужках
    # для діагностики - краще недоперекласти, ніж збрехати про причину).
    param([string]$RawMessage)
    if (-not $RawMessage) { return $RawMessage }
    $patterns = @(
        @{ Pattern = 'network|internet|resolve|remote name|connection|timed? ?out'; Text = "Немає з'єднання з інтернетом або сервер недоступний" }
        @{ Pattern = 'access is denied|unauthorized|permission'; Text = 'Відмовлено в доступі (перевірте права адміністратора)' }
        @{ Pattern = "is not recognized|not recognized as the name|isn'?t recognized"; Text = 'Потрібна команда відсутня в цій збірці/редакції Windows' }
        @{ Pattern = 'cannot find path|does not exist|could not be found|not found'; Text = 'Вказаний шлях або ресурс не знайдено' }
        @{ Pattern = 'disk|not enough space'; Text = 'Недостатньо місця на диску' }
        @{ Pattern = 'already exists'; Text = 'Такий об''єкт уже існує' }
        @{ Pattern = 'operation is not supported|not supported on this platform'; Text = 'Ця дія не підтримується на поточній системі' }
    )
    foreach ($p in $patterns) {
        if ($RawMessage -match $p.Pattern) { return "$($p.Text) ($RawMessage)" }
    }
    return $RawMessage
}
#endregion

#region === Settings & State ===
$scriptVersion = '5.0.0'
$logDir = Join-Path $PSScriptRoot 'log'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
# Не смітимо в корені теки: усі логи йдуть у log/, лишаємо 3 останні (включно з новим).
Get-ChildItem -Path $PSScriptRoot -Filter 'Ukrainizator_*.log' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $logDir -Filter 'Ukrainizator_*.log' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 | Remove-Item -Force -ErrorAction SilentlyContinue
$logFile = Join-Path $logDir "Ukrainizator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$backupDir = Join-Path $PSScriptRoot 'backup'
if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
# Якщо лишились старі знімки в корені теки (з версій до 5.0.0) - переносимо в backup/,
# щоб -Revert однаково їх бачив і корінь теки більше не засмічувався.
Get-ChildItem -Path $PSScriptRoot -Filter 'Ukrainizator_backup_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
    Move-Item -Path $_.FullName -Destination (Join-Path $backupDir $_.Name) -Force -ErrorAction SilentlyContinue
}

$startTime = Get-Date
$global:steps = @()
$global:FailedSteps = New-Object System.Collections.ArrayList   # для "продовжити після помилки" - підсумок наприкінці
$global:BackupData = [ordered]@{}                                # знімок налаштувань "до" - для -Revert

function Add-StepIssue {
    param([int]$id, [string]$name, [string]$message)
    [void]$global:FailedSteps.Add([pscustomobject]@{ Id = $id; Name = $name; Message = $message })
}
#endregion

#region === Modern UI Engine (ANSI / VT, no fixed console geometry needed) ===
# Замість малювання за абсолютними координатами буфера (крихко: залежить
# від розміру вікна/буфера і ламається у Windows Terminal), кадр малюється
# повністю, а для оновлення курсор просто піднімається відносно ПОТОЧНОГО
# положення на потрібну кількість рядків і все нижче очищується. Це працює
# однаково надійно у Windows Terminal і класичному conhost, і не залежить
# від розміру консолі.

$ESC = [char]27
$global:UseAnsi = $false
$global:AnsiLinesDrawn = 0

$Palette = @{
    Reset   = "$ESC[0m"
    Bold    = "$ESC[1m"
    Dim     = "$ESC[2m"
    Blue    = "$ESC[38;2;70;140;255m"    # яскравий блакитний (прапор + акцент)
    Gold    = "$ESC[38;2;255;209;70m"    # яскраве золото (прапор)
    Yellow  = "$ESC[38;2;255;209;70m"    # аліас на Gold - для сумісності зі старим кодом
    Green   = "$ESC[38;2;60;222;141m"    # соковитий смарагдовий (успіх)
    Red     = "$ESC[38;2;255;90;95m"     # яскраво-коралово-червоний (помилка)
    Cyan    = "$ESC[38;2;56;225;225m"    # електрик-бірюза (інфо/спінер)
    Magenta = "$ESC[38;2;199;125;255m"   # акцент
    Gray    = "$ESC[38;2;150;162;180m"   # м'якший, але контрастніший сірий
    White   = "$ESC[38;2;245;247;250m"   # яскраво-білий
}

function Get-GradientColor {
    # Плавний перехід від блакитного до золотого (прапор України) за t=0..1
    param([double]$T)
    if ($T -lt 0) { $T = 0 }; if ($T -gt 1) { $T = 1 }
    $r = [int](70  + (255 - 70)  * $T)
    $g = [int](140 + (209 - 140) * $T)
    $b = [int](255 + (70  - 255) * $T)
    return "$ESC[38;2;${r};${g};${b}m"
}

$global:UIState = @{
    Percent       = 0
    ProgressLabel = ''
    InfoLines     = @()
    InfoStyle     = 'Normal'
    RecentLogs    = New-Object System.Collections.ArrayList
    PromptActive  = $false
    PromptText    = ''
    Footer        = @()
    SpinnerFrame  = 0
}

function Write-Raw {
    param([string]$Text)
    try { [Console]::Out.Write($Text) } catch {}
}

function Set-CursorVisible {
    param([bool]$Visible)
    try { [Console]::CursorVisible = $Visible } catch {}
}

function Enable-VirtualTerminal {
    try {
        if (-not ('NativeConsole.Methods' -as [type])) {
            Add-Type -Namespace NativeConsole -Name Methods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
'@ -ErrorAction Stop
        }
        $handle = [NativeConsole.Methods]::GetStdHandle(-11) # STD_OUTPUT_HANDLE
        $mode = 0
        if (-not [NativeConsole.Methods]::GetConsoleMode($handle, [ref]$mode)) { return $false }
        $newMode = $mode -bor 0x0004 # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        if (-not [NativeConsole.Methods]::SetConsoleMode($handle, $newMode)) { return $false }
        return $true
    } catch {
        Write-DebugLog "Enable-VirtualTerminal failed: $($_.Exception.Message)"
        return $false
    }
}

function Initialize-UI {
    $global:UseAnsi = $false
    try {
        if ([Console]::IsOutputRedirected) { return }
    } catch {}
    # Раніше тут була додаткова перевірка $Host.Name -notmatch 'ConsoleHost',
    # яка на частині систем (напр. запуск через ярлик з підвищенням прав,
    # деякі обгортки-інсталятори) хибно відсікала цілком нормальну консоль
    # і назавжди вимикала "живий" інтерфейс, залишаючи лише плаский лог.
    # Тепер орієнтуємось виключно на реальний результат спроби увімкнути
    # VT-режим (ENABLE_VIRTUAL_TERMINAL_PROCESSING).
    if (Enable-VirtualTerminal) {
        $global:UseAnsi = $true
    }
}

function Get-PanelWidth {
    $w = 76
    try {
        $cw = $Host.UI.RawUI.WindowSize.Width
        if ($cw -gt 0) { $w = [Math]::Max(60, [Math]::Min(96, $cw - 4)) }
    } catch {}
    return $w
}

function Get-VisualLength {
    param([string]$Text)
    $pattern = [regex]::Escape([string]$ESC) + '\[[0-9;]*m'
    return ([regex]::Replace($Text, $pattern, '')).Length
}

function Set-PaddedLine {
    param([string]$Text, [int]$Width)
    $len = Get-VisualLength $Text
    if ($len -ge $Width) { return $Text }
    return $Text + (' ' * ($Width - $len))
}

function Get-StepIconPlain {
    param($Step)
    switch ($Step.status) {
        'success' { return @{ Char = [string][char]0x2713; Color = 'Green' } }
        'error'   { return @{ Char = [string][char]0x2717; Color = 'Red' } }
        'skipped' { return @{ Char = [string][char]0x25CF; Color = 'Yellow' } }
        default   { return @{ Char = [string][char]0x25CF; Color = 'DarkGray' } }
    }
}

function Show-PlainHeader {
    $w = 50
    $top = [char]0x256D + ([string]([char]0x2500) * $w) + [char]0x256E
    $bot = [char]0x2570 + ([string]([char]0x2500) * $w) + [char]0x256F
    Write-Host ''
    Write-Host "  $top" -ForegroundColor Blue
    Write-Host ("  {0}  УКРАЇНІЗАТОР  v{1}" -f [char]0x2502, $scriptVersion) -ForegroundColor White
    Write-Host ("  {0}  Встановлення української мови в Windows" -f [char]0x2502) -ForegroundColor Cyan
    Write-Host "  $bot" -ForegroundColor Blue
    Write-Host ''
}

function Get-StepIcon {
    param($Step)
    switch ($Step.status) {
        'success' { return "$($Palette.Green)$([char]0x2713)$($Palette.Reset)" }
        'error'   { return "$($Palette.Red)$([char]0x2717)$($Palette.Reset)" }
        'skipped' { return "$($Palette.Yellow)~$($Palette.Reset)" }
        'running' {
            $frames = @([char]0x280B,[char]0x2819,[char]0x2839,[char]0x2838,[char]0x283C,[char]0x2834,[char]0x2826,[char]0x2827,[char]0x2807,[char]0x280F)
            $f = $frames[$global:UIState.SpinnerFrame % $frames.Count]
            return "$($Palette.Cyan)$f$($Palette.Reset)"
        }
        default   { return "$($Palette.Gray)$([char]0x00B7)$($Palette.Reset)" }
    }
}

function New-Frame {
    $w = Get-PanelWidth
    $P = $Palette
    $lines = New-Object System.Collections.Generic.List[string]

    # --- Header ---
    $top = [char]0x256D + ([string]([char]0x2500) * ($w - 2)) + [char]0x256E
    $bot = [char]0x2570 + ([string]([char]0x2500) * ($w - 2)) + [char]0x256F
    $titleLeft  = " $($P.Bold)$($P.White)УКРАЇНІЗАТОР$($P.Reset)"
    $titleRight = "$($P.Dim)v$scriptVersion$($P.Reset) "
    $gap = [Math]::Max(1, ($w - 2) - (Get-VisualLength $titleLeft) - (Get-VisualLength $titleRight))
    $titleLine = $titleLeft + (' ' * $gap) + $titleRight
    $subtitle = " $($P.Bold)$($P.Gold)Встановлення української мови в Windows$($P.Reset)"

    $lines.Add("$($P.Blue)$top$($P.Reset)")
    $lines.Add("$($P.Blue)$([char]0x2502)$($P.Reset)" + (Set-PaddedLine $titleLine ($w - 2)) + "$($P.Blue)$([char]0x2502)$($P.Reset)")
    $lines.Add("$($P.Blue)$([char]0x2502)$($P.Reset)" + (Set-PaddedLine $subtitle ($w - 2)) + "$($P.Blue)$([char]0x2502)$($P.Reset)")
    $lines.Add("$($P.Gold)$bot$($P.Reset)")
    $lines.Add('')

    # --- Steps ---
    foreach ($step in $global:steps) {
        $icon = Get-StepIcon $step
        $idText = $step.id.ToString().PadLeft(2)
        $nameRaw = " $($P.Magenta)$idText.$($P.Reset)  $($step.name)"
        $nameCol = Set-PaddedLine $nameRaw 48
        $resText = ''
        if ($step.result) { $resText = "$($P.Dim)$([char]0x2192)$($P.Reset) $($step.result)" }
        $nameColor = $P.Dim
        switch ($step.status) {
            'success' { $nameColor = $P.White }
            'error'   { $nameColor = $P.Red }
            'running' { $nameColor = $P.White }
        }
        $lines.Add("  $icon  $nameColor$nameCol$($P.Reset) $resText")
    }
    $lines.Add('')

    # --- Progress bar ---
    $barSize = 36
    $pct = [Math]::Max(0, [Math]::Min(100, $global:UIState.Percent))
    $filled = [int][math]::Floor($pct / 100 * $barSize)
    $empty = $barSize - $filled
    $barChars = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $filled; $i++) {
        $t = if ($barSize -gt 1) { $i / [double]($barSize - 1) } else { 0 }
        [void]$barChars.Append("$(Get-GradientColor $t)$([char]0x2588)")
    }
    [void]$barChars.Append($P.Reset)
    [void]$barChars.Append("$($P.Dim)" + ([string]([char]0x2591) * $empty) + "$($P.Reset)")
    $bar = $barChars.ToString()
    $pctColor = if ($pct -ge 100) { $P.Gold } else { $P.White }
    $pctText = "$($P.Bold)$pctColor$($pct.ToString().PadLeft(3))%$($P.Reset)"
    $labelText = ''
    if ($global:UIState.ProgressLabel) { $labelText = "  $($P.Dim)$($global:UIState.ProgressLabel)$($P.Reset)" }
    $lines.Add("  $bar  $pctText$labelText")

    # --- Recent log ---
    if ($global:UIState.RecentLogs.Count -gt 0) {
        $lines.Add('')
        $lines.Add("  $($P.Dim)$([string]([char]0x2500) * ($w - 4))$($P.Reset)")
        foreach ($lg in $global:UIState.RecentLogs) {
            $lines.Add("  $lg")
        }
    }

    # --- Footer (completion banner) ---
    if ($global:UIState.Footer.Count -gt 0) {
        $lines.Add('')
        foreach ($fl in $global:UIState.Footer) { $lines.Add($fl) }
    }

    # --- Contextual info panel / prompt (always last -> cursor lands here) ---
    if ($global:UIState.InfoLines.Count -gt 0 -or $global:UIState.PromptActive) {
        $lines.Add('')
        $accent = $P.Cyan
        if ($global:UIState.InfoStyle -eq 'Warning') { $accent = $P.Yellow }
        if ($global:UIState.InfoStyle -eq 'Error')   { $accent = $P.Red }
        foreach ($il in $global:UIState.InfoLines) {
            $lines.Add("  $accent$([char]0x2502)$($P.Reset) $il")
        }
        if ($global:UIState.PromptActive) {
            if ($global:UIState.InfoLines.Count -gt 0) { $lines.Add('') }
            $lines.Add("  $($P.Bold)$($P.Yellow)?$($P.Reset) $($global:UIState.PromptText) ")
        }
    }

    return $lines.ToArray()
}

function Show-Frame {
    if (-not $global:UseAnsi) { return }
    $lines = New-Frame
    $sb = New-Object System.Text.StringBuilder
    # Раніше тут курсор піднімався на розраховану кількість рядків і
    # стирав "далі до кінця екрана" - але якщо термінал у перші миті
    # роботи звітував неточну ширину вікна, довгі рядки рамки переносились,
    # реальна кількість візуальних рядків не збігалась з розрахунком, і
    # старий кадр стирався не повністю (звідси накладання на старті).
    # Повне очищення екрана перед кожним кадром прибирає цю залежність
    # повністю - результат завжди коректний незалежно від ширини вікна.
    [void]$sb.Append("$ESC[2J$ESC[H")
    [void]$sb.Append(($lines -join "`n"))
    Write-Raw $sb.ToString()
    $global:AnsiLinesDrawn = $lines.Count
}

function Set-StepStatus {
    param([int]$id, [string]$status, [string]$result = '', [string]$details = '')
    $step = $global:steps | Where-Object { $_.id -eq $id }
    $step.status = $status
    $step.result = $result
    $step.details = $details

    if ($status -eq 'success' -or $status -eq 'skipped') {
        try { [Console]::Beep(350 + ($id * 50), 80) } catch {}
    }

    if ($global:UseAnsi) {
        Show-Frame
        return
    }

    # Плаский режим: пропускаємо проміжний стан 'running' (щоб не було двох
    # рядків на кожен крок - "запущено" і потім "готово"), друкуємо лише
    # фінальний результат одним акуратним рядком з крапками-заповнювачами.
    if ($status -eq 'running') { return }

    $icon = Get-StepIconPlain $step
    $idText = "$($id)."
    $namePart = " $idText $($step.name) "
    $leaderWidth = 50
    $dots = ''
    if ($namePart.Length -lt $leaderWidth) {
        $dots = [string]([char]0x00B7) * ($leaderWidth - $namePart.Length)
    }
    Write-Host -NoNewline '  '
    Write-Host -NoNewline $icon.Char -ForegroundColor $icon.Color
    Write-Host -NoNewline "$namePart" -ForegroundColor White
    Write-Host -NoNewline $dots -ForegroundColor DarkGray
    if ($result) {
        Write-Host " $result" -ForegroundColor $icon.Color
    } else {
        Write-Host ''
    }
}

function Show-ProgressBar {
    param([int]$Percent, [string]$Label = '')
    $global:UIState.Percent = $Percent
    $global:UIState.ProgressLabel = $Label
    if ($global:UseAnsi) { Show-Frame }
}

function Set-InfoPanel {
    param([string[]]$Lines, [string]$Style = 'Normal')
    $global:UIState.InfoLines = $Lines
    $global:UIState.InfoStyle = $Style
    if ($global:UseAnsi) {
        Show-Frame
        return
    }
    $fg = 'Cyan'
    if ($Style -eq 'Warning') { $fg = 'DarkYellow' }
    if ($Style -eq 'Error')   { $fg = 'Red' }
    Write-Host ''
    foreach ($l in $Lines) { Write-Host ("  {0} {1}" -f [char]0x2502, $l) -ForegroundColor $fg }
    Write-Host ''
}

function Clear-InfoPanel {
    $global:UIState.InfoLines = @()
    $global:UIState.InfoStyle = 'Normal'
    if ($global:UseAnsi) { Show-Frame }
}

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8

    if ($global:UseAnsi) {
        $entryColor = $Palette.Gray
        if ($Color -match 'Green')  { $entryColor = $Palette.Green }
        if ($Color -match 'Yellow') { $entryColor = $Palette.Yellow }
        if ($Color -match 'Red')    { $entryColor = $Palette.Red }
        $formatted = "$($Palette.Dim)$timestamp$($Palette.Reset)  $entryColor$Message$($Palette.Reset)"
        [void]$global:UIState.RecentLogs.Add($formatted)
        while ($global:UIState.RecentLogs.Count -gt 3) { $global:UIState.RecentLogs.RemoveAt(0) }
        Show-Frame
    } else {
        Write-Host "  $logMessage" -ForegroundColor $Color
    }
}

function Read-LiveInput {
    param([string]$Default)
    $buffer = New-Object System.Text.StringBuilder
    [void]$buffer.Append($Default)
    while ($true) {
        $keyInfo = [Console]::ReadKey($true)
        if ($keyInfo.Key -eq [ConsoleKey]::Enter) { break }
        elseif ($keyInfo.Key -eq [ConsoleKey]::Backspace) {
            if ($buffer.Length -gt 0) {
                [void]$buffer.Remove($buffer.Length - 1, 1)
                Write-Raw "`b `b"
            }
        } else {
            $c = $keyInfo.KeyChar
            if ($c -and -not [char]::IsControl($c)) {
                [void]$buffer.Append($c)
                Write-Raw ([string]$c)
            }
        }
    }
    return $buffer.ToString()
}

function Show-Prompt {
    param([string]$Text, [string]$Default = 'Y')
    if ($global:UseAnsi) {
        $global:UIState.PromptActive = $true
        $global:UIState.PromptText = $Text
        Show-Frame
        Write-Raw $Default
        $result = Read-LiveInput -Default $Default
        $global:UIState.PromptActive = $false
        return $result
    } else {
        Write-Host ''
        Write-Host ("  {0} {1} " -f [char]0x2192, $Text) -NoNewline -ForegroundColor Yellow
        Write-Host "[$Default]: " -NoNewline -ForegroundColor DarkGray
        $r = Read-Host
        if ([string]::IsNullOrWhiteSpace($r)) { return $Default }
        return $r.Trim()
    }
}

function Restore-Console {
    Set-CursorVisible $true
    if ($global:UseAnsi) { Write-Raw "$ESC[0m" }
}

function Write-ErrorExit {
    param([string]$Message, [int]$stepId)
    Set-StepStatus -id $stepId -status 'error' -result (Get-LocalizedMessage 'error_prefix')
    try { [Console]::Beep(300, 300) } catch {}
    Set-InfoPanel -Lines @($Message) -Style 'Error'
    Write-Log "$(Get-LocalizedMessage 'error_log_prefix')$Message" -Color Red
    if ($global:UseAnsi) { Write-Raw "`n`n" }
    Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    Restore-Console
    exit 1
}

function Show-CompletionBanner {
    $elapsed = (Get-Date) - $startTime
    $P = $Palette
    $global:UIState.Footer = @(
        "  $($P.Green)$($P.Bold)$([char]0x2713) $(Get-LocalizedMessage 'all_done')$($P.Reset)",
        "  $($P.Dim)$(Get-LocalizedMessage 'time_elapsed') $($elapsed.Minutes)m $($elapsed.Seconds)s$($P.Reset)",
        "  $($P.Dim)$(Get-LocalizedMessage 'log_file') $logFile$($P.Reset)"
    )
    if ($global:UseAnsi) {
        Show-Frame
        return
    }
    $w = 50
    $top = [char]0x256D + ([string]([char]0x2500) * $w) + [char]0x256E
    $bot = [char]0x2570 + ([string]([char]0x2500) * $w) + [char]0x256F
    Write-Host ''
    Write-Host "  $top" -ForegroundColor Green
    Write-Host ("  {0}  {1} {2}" -f [char]0x2502, [char]0x2713, (Get-LocalizedMessage 'all_done')) -ForegroundColor Green
    Write-Host ("  {0}  {1} {2}" -f [char]0x2502, (Get-LocalizedMessage 'time_elapsed'), "$($elapsed.Minutes)m $($elapsed.Seconds)s") -ForegroundColor DarkGray
    Write-Host ("  {0}  {1} {2}" -f [char]0x2502, (Get-LocalizedMessage 'log_file'), $logFile) -ForegroundColor DarkGray
    Write-Host "  $bot" -ForegroundColor Green
}
#endregion

#region === Швидка перевірка "вже налаштовано" (idempotency) ===
function Test-AlreadyUkrainized {
    try {
        $sysLocale = (Get-WinSystemLocale).Name
        $uiOverride = (Get-WinUILanguageOverride -ErrorAction SilentlyContinue).Name
        $langList = Get-WinUserLanguageList
        $hasUk = $langList | Where-Object { $_.LanguageTag -eq 'uk-UA' }
        $hasRu = $langList | Where-Object { $_.LanguageTag -match 'ru' }
        $geoId = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
        return ($sysLocale -eq 'uk-UA' -and $uiOverride -eq 'uk-UA' -and $hasUk -and (-not $hasRu) -and $geoId -eq 240)
    } catch {
        return $false
    }
}
function Show-CountdownReboot {
    param([int]$Seconds = 15)
    for ($s = $Seconds; $s -gt 0; $s--) {
        Set-InfoPanel -Lines @("$(Get-LocalizedMessage 'rebooting') Перезавантаження через $s с... (натисніть будь-яку клавішу, щоб скасувати)")
        try {
            if ([Console]::KeyAvailable) {
                [Console]::ReadKey($true) | Out-Null
                return $false
            }
        } catch {}
        Start-Sleep -Seconds 1
    }
    return $true
}

#endregion

# === Bootstrap ===
Initialize-UI
if ($global:UseAnsi) {
    Set-CursorVisible $false
    Write-Raw "$ESC[2J$ESC[H"
} else {
    try { Clear-Host } catch {}
    Show-PlainHeader
}
try {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { try { [Console]::CursorVisible = $true } catch {} } -ErrorAction SilentlyContinue | Out-Null
} catch {}

if (-not (Read-LocalizationFile $global:CurrentLanguage)) {
    $global:CurrentLanguage = 'en-US'
    if (-not (Read-LocalizationFile $global:CurrentLanguage)) {
        Restore-Console
        Write-Host "Fatal Error: Could not load any localization files from $scriptLocalePath. Exiting." -ForegroundColor Red
        exit 1
    }
}

#region === Відкат (-Revert) ===
if ($Revert) {
    Write-Log 'Запущено режим відкату (-Revert)' -Color DarkYellow
    $backupPattern = Join-Path $backupDir 'Ukrainizator_backup_*.json'
    $lastBackup = Get-ChildItem -Path $backupPattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $lastBackup) {
        Set-InfoPanel -Style 'Error' -Lines @('Резервний знімок не знайдено.', 'Відкат можливий лише після хоча б одного звичайного запуску скрипта.')
        Write-Log 'Відкат неможливий: файл резервної копії не знайдено' -Color Red
        Write-Host ''
        Write-Host '  Натисніть будь-яку клавішу, щоб завершити...' -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        Restore-Console
        exit 1
    }
    try {
        $bk = Get-Content -Path $lastBackup.FullName -Raw | ConvertFrom-Json
        Set-InfoPanel -Lines @(
            "Знайдено знімок від $($lastBackup.LastWriteTime)",
            "Буде відновлено: SystemLocale=$($bk.SystemLocale), UILanguage=$($bk.UILanguage), Culture=$($bk.Culture)"
        )
        $go = Show-Prompt -Text 'Відновити ці налаштування? (Y/N)' -Default 'Y'
        if ($go -notin @('Y','y','Yes','YES')) {
            Write-Log 'Відкат скасовано користувачем' -Color DarkYellow
            Restore-Console
            exit 0
        }
        if (-not $WhatIf) {
            if ($bk.SystemLocale) { Set-WinSystemLocale -SystemLocale $bk.SystemLocale -ErrorAction SilentlyContinue }
            if ($bk.Culture)      { Set-Culture -CultureInfo $bk.Culture -ErrorAction SilentlyContinue }
            if ($bk.UILanguage)   { Set-WinUILanguageOverride -Language $bk.UILanguage -ErrorAction SilentlyContinue }
            if ($bk.GeoId)        { Set-WinHomeLocation -GeoId $bk.GeoId -ErrorAction SilentlyContinue }
            if ($bk.LanguageList) {
                try {
                    $ll = New-WinUserLanguageList -Language $bk.LanguageList[0]
                    for ($i = 1; $i -lt $bk.LanguageList.Count; $i++) { $ll.Add($bk.LanguageList[$i]) }
                    Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction SilentlyContinue
                } catch {}
            }
            Write-Log 'Попередні налаштування відновлено' -Color DarkGreen
        } else {
            Write-Log '[WhatIf] Відкат НЕ виконано (лише перегляд)' -Color DarkYellow
        }
        Clear-InfoPanel
        Show-CompletionBanner
        Restore-Console
        Write-Host ''
        Write-Host '  Рекомендується перезавантажити комп''ютер, щоб зміни набули чинності.' -ForegroundColor DarkYellow
        Write-Host '  Натисніть будь-яку клавішу, щоб завершити...' -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        exit 0
    } catch {
        Write-Host ''
        Write-Host "  Не вдалося прочитати резервну копію: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Натисніть будь-яку клавішу, щоб завершити...' -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        Restore-Console
        exit 1
    }
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
    @{ id = 12; name = 'Перевірка результату';                              status = 'pending'; result = ''; details = '' }
)

Show-Frame
Write-Log "$(Get-LocalizedMessage 'starting_ukrainizator') v$scriptVersion"
if ($WhatIf) { Write-Log '[WhatIf] Режим попереднього перегляду: жодних реальних змін внесено НЕ буде' -Color DarkYellow }

#region === 0. Швидка перевірка "вже налаштовано" ===
if (-not $Force -and -not $WhatIf) {
    if (Test-AlreadyUkrainized) {
        Set-InfoPanel -Lines @(
            'Схоже, систему вже повністю українізовано (мова, регіон, розкладки).',
            'Повторний повний прогін не обов''язковий.'
        )
        Write-Log 'Швидка перевірка: система вже налаштована' -Color DarkGreen
        if ($Silent) {
            Write-Log 'Тихий режим: завершення без повторної обробки (додайте -Force для примусового повтору)' -Color DarkGreen
            Restore-Console
            exit 0
        }
        $again = Show-Prompt -Text 'Все одно виконати повний прогін ще раз? (y/N)' -Default 'N'
        if ($again -notin @('Y','y','Yes','YES')) {
            Clear-InfoPanel
            Write-Log 'Користувач підтвердив, що повторна обробка не потрібна' -Color DarkGreen
            Restore-Console
            exit 0
        }
        Clear-InfoPanel
    }
}
#endregion

#region === Резервний знімок поточних налаштувань (для -Revert) ===
if (-not $WhatIf) {
    try {
        $backupObj = [ordered]@{
            Timestamp     = (Get-Date).ToString('o')
            SystemLocale  = (Get-WinSystemLocale -ErrorAction SilentlyContinue).Name
            UILanguage    = (Get-WinUILanguageOverride -ErrorAction SilentlyContinue).Name
            Culture       = (Get-Culture).Name
            GeoId         = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
            LanguageList  = @((Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }))
        }
        $backupFile = Join-Path $backupDir "Ukrainizator_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $backupObj | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
        # Лишаємо тільки 5 останніх знімків, щоб не смітити теку
        Get-ChildItem -Path (Join-Path $backupDir 'Ukrainizator_backup_*.json') -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Log "Резервний знімок налаштувань збережено: $(Split-Path $backupFile -Leaf) (для відкату: -Revert)" -Color DarkGreen
    } catch {
        Write-Log "Не вдалося зберегти резервний знімок: $(Get-FriendlyErrorMessage $_.Exception.Message)" -Color DarkYellow
    }
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
    $osInfo = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $global:WinBuild = [int]$osInfo.CurrentBuildNumber
    $global:WinDisplayVersion = if ($osInfo.DisplayVersion) { $osInfo.DisplayVersion } else { $osInfo.ReleaseId }
    $global:WinProductName = $osInfo.ProductName
    Write-Log "Виявлено: $($global:WinProductName), $($global:WinDisplayVersion) (build $($global:WinBuild))" -Color DarkGreen
} catch {
    $global:WinBuild = 0
    $global:WinDisplayVersion = 'невідомо'
    $global:WinProductName = 'невідома збірка Windows'
    Write-Log 'Не вдалося визначити збірку Windows - буде використано універсальний (DISM) спосіб встановлення мови' -Color DarkYellow
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
if ($Silent) {
    Set-StepStatus -id 3 -status 'success' -result 'Auto'
    Write-Log (Get-LocalizedMessage 'confirmation_skipped_silent') -Color DarkGreen
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
    Checkpoint-Computer -Description "Before running Ukrainizator" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
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
if ($Silent) {
    $installMode = $Mode
    $modeText = if ($Mode -eq 'All') { (Get-LocalizedMessage 'all_users_auto') } else { (Get-LocalizedMessage 'current_user_auto') }
    Set-StepStatus -id 5 -status 'success' -result $modeText
    Write-Log "$(Get-LocalizedMessage 'silent_mode_selected') $modeText" -Color DarkGreen
} else {
    Set-InfoPanel -Lines @(
        (Get-LocalizedMessage 'apply_to'),
        "  [A] $(Get-LocalizedMessage 'all_users_recommended')",
        "  [C] $(Get-LocalizedMessage 'current_user_only')"
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
    Write-Log "$(Get-LocalizedMessage 'selected_mode')$modeText" -Color DarkGreen
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
        Set-StepStatus -id 6 -status 'skipped' -result 'DISM (запасний спосіб)'
        Write-Log 'Install-Language недоступний у цій збірці - буде використано універсальний спосіб через DISM (Add-WindowsCapability)' -Color DarkYellow
    } else {
        Set-StepStatus -id 6 -status 'skipped' -result 'Недоступно'
        Add-StepIssue -id 6 -name (Get-LocalizedMessage 'modules_check') -message 'Ані Install-Language, ані DISM-командлети недоступні на цій системі'
        Write-Log (Get-LocalizedMessage 'languagemanagement_not_available') -Color DarkYellow
    }
}
#endregion

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
    Set-StepStatus -id 7 -status 'skipped' -result 'Пропущено (немає способу)'
    Add-StepIssue -id 7 -name (Get-LocalizedMessage 'language_pack_installation') -message 'Немає жодного доступного способу встановлення мовного пакету на цій системі'
    Write-Log 'Крок пропущено: жоден спосіб встановлення мовного пакету недоступний на цій системі' -Color DarkYellow
} else {
    Write-Log (Get-LocalizedMessage 'installing_language' $targetLanguageTag) -Color DarkYellow
    try {
        if ($global:UseModernLanguageApi) {
            Install-Language -Language $targetLanguageTag -CopyToSettings -ExcludeFeatures -ErrorAction Stop
        } else {
            # Універсальний DISM-шлях: базовий мовний пакет + додаткові
            # компоненти (шрифти, мовлення, рукопис), якщо доступні саме на
            # цій збірці. Базовий пакет - обов'язковий, решта - best-effort.
            Add-WindowsCapability -Online -Name "Language.Basic~~~$targetLanguageTag~0.0.1.0" -ErrorAction Stop
            foreach ($extra in @('Language.Fonts.Cyrl', 'Language.Handwriting', 'Language.OCR', 'Language.Speech', 'Language.TextToSpeech')) {
                try {
                    $capName = "$extra~~~$targetLanguageTag~0.0.1.0"
                    $capInfo = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
                    if ($capInfo -and $capInfo.State -ne 'Installed') {
                        Add-WindowsCapability -Online -Name $capName -ErrorAction Stop | Out-Null
                    }
                } catch {
                    Write-DebugLog "Додатковий компонент $extra недоступний на цій збірці - пропущено"
                }
            }
            $ll = Get-WinUserLanguageList
            if (-not ($ll | Where-Object { $_.LanguageTag -eq $targetLanguageTag })) {
                $ll.Add($targetLanguageTag)
                Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction SilentlyContinue
            }
        }
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

#region === 8. Interface ===
Set-StepStatus -id 8 -status 'running'
Show-ProgressBar -Percent 70 -Label (Get-LocalizedMessage 'interface_label')
if ($WhatIf) {
    Set-StepStatus -id 8 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б встановлено мову інтерфейсу uk-UA' -Color DarkYellow
} else {
try {
    Set-WinUILanguageOverride -Language 'uk-UA' -ErrorAction Stop
    $langCode = '0422'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value $langCode -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value $langCode -ErrorAction Stop

    if ($installMode -eq 'All') {
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
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

#region === 9. Regional Formats ===
Set-StepStatus -id 9 -status 'running'
Show-ProgressBar -Percent 80 -Label (Get-LocalizedMessage 'regional_formats_label')
if ($WhatIf) {
    Set-StepStatus -id 9 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б встановлено регіон uk-UA, часовий пояс, понеділок як перший день тижня' -Color DarkYellow
} else {
try {
    Set-Culture -CultureInfo 'uk-UA' -ErrorAction Stop
    Set-WinSystemLocale -SystemLocale 'uk-UA' -ErrorAction Stop
    $geoId = 240
    Set-WinHomeLocation -GeoId $geoId -ErrorAction Stop

    # Часовий пояс України
    try {
        Set-TimeZone -Id 'FLE Standard Time' -ErrorAction Stop
        Write-Log 'Часовий пояс встановлено: FLE Standard Time (Київ)' -Color DarkGreen
    } catch {
        Write-Log "Не вдалося встановити часовий пояс: $(Get-FriendlyErrorMessage $_.Exception.Message)" -Color DarkYellow
    }

    # Перший день тижня - понеділок, символ валюти - гривня (₴), явно в реєстрі,
    # оскільки Set-Culture не завжди повністю оновлює legacy NLS-ключі реєстру.
    try {
        $intlPath = 'HKCU:\Control Panel\International'
        Set-ItemProperty -Path $intlPath -Name 'iFirstDayOfWeek' -Value '0' -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $intlPath -Name 'sCurrency' -Value ([char]0x20B4) -ErrorAction SilentlyContinue
        Write-Log 'Перший день тижня (пн) і символ валюти (₴) встановлено' -Color DarkGreen
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

#region === 10. Derussification & Layouts ===
Set-StepStatus -id 10 -status 'running'
Show-ProgressBar -Percent 90 -Label (Get-LocalizedMessage 'layouts_label')
if ($WhatIf) {
    Set-StepStatus -id 10 -status 'skipped' -result '[WhatIf]'
    Write-Log '[WhatIf] Було б видалено ru-* мову/розкладку/пакети розпізнавання мовлення та рукопису' -Color DarkYellow
} else {
try {
    $list = Get-WinUserLanguageList
    $ruLanguages = $list | Where-Object { $_.LanguageTag -match 'ru' }
    foreach ($ruLang in $ruLanguages) {
        $list.Remove($ruLang)
        Write-Log (Get-LocalizedMessage 'removed_russian_language' $ruLang.LanguageTag) -Color DarkYellow
    }

    $ll = New-WinUserLanguageList -Language 'uk-UA'
    $defaultLangIMT = '0422:00000422'
    $primaryLang = $ll | Where-Object { $_.LanguageTag -eq 'uk-UA' }
    $primaryLang.InputMethodTips.Clear()
    $primaryLang.InputMethodTips.Add($defaultLangIMT)

    $secondaryLanguageTag = 'en-US'
    $secondaryLangIMT = '0409:00000409'
    $ll.Add($secondaryLanguageTag)
    $secondaryLang = $ll | Where-Object { $_.LanguageTag -eq $secondaryLanguageTag }
    $secondaryLang.InputMethodTips.Clear()
    $secondaryLang.InputMethodTips.Add($secondaryLangIMT)

    Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction Stop

    $preloadPath = 'HKCU:\Keyboard Layout\Preload'
    if (Test-Path $preloadPath) {
        $preloads = Get-ItemProperty -Path $preloadPath
        foreach ($prop in $preloads.PSObject.Properties) {
            if ($prop.Value -eq '00000419') {
                Remove-ItemProperty -Path $preloadPath -Name $prop.Name -Force -ErrorAction SilentlyContinue
                Write-Log (Get-LocalizedMessage 'removed_russian_layout') -Color DarkYellow
            }
        }
    }

    $togglePath = 'HKCU:\Keyboard Layout\Toggle'
    if (-not (Test-Path $togglePath)) { New-Item -Path $togglePath -Force | Out-Null }
    Set-ItemProperty -Path $togglePath -Name 'Hotkey' -Value 1 -ErrorAction Stop

    # --- Глибша дерусифікація ---
    # 1) Додаткові ru-* компоненти Windows (розпізнавання мовлення, рукописне
    #    введення, синтез мовлення) - вони НЕ прибираються самим лише видаленням
    #    мови зі списку розкладок, а встановлюються/видаляються окремо.
    try {
        $ruCapabilities = Get-WindowsCapability -Online -ErrorAction Stop |
            Where-Object { $_.Name -match '^Language\.(Speech|Handwriting|TextToSpeech|OCR)~.*~ru-RU~' -and $_.State -eq 'Installed' }
        foreach ($cap in $ruCapabilities) {
            try {
                Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                Write-Log "Видалено компонент: $($cap.Name)" -Color DarkYellow
            } catch {
                Write-Log "Не вдалося видалити $($cap.Name): $(Get-FriendlyErrorMessage $_.Exception.Message)" -Color DarkYellow
            }
        }
        if ($ruCapabilities.Count -eq 0) { Write-Log 'Додаткових ru-* компонентів (мовлення/рукопис/OCR) не знайдено' -Color DarkGreen }
    } catch {
        Write-Log "Перевірку додаткових мовних компонентів пропущено: $(Get-FriendlyErrorMessage $_.Exception.Message)" -Color DarkYellow
    }

    # 2) Кеш підказок під час набору тексту (може містити напрацьовані ru-слова).
    #    Офіційно документований шлях Microsoft для скидання персоналізації вводу.
    try {
        $ipPath = 'HKCU:\Software\Microsoft\InputPersonalization'
        if (Test-Path $ipPath) {
            Set-ItemProperty -Path $ipPath -Name 'RestrictImplicitTextCollection' -Value 1 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $ipPath -Name 'RestrictImplicitInkCollection' -Value 1 -ErrorAction SilentlyContinue
        }
        $harvesterPath = "$env:LOCALAPPDATA\Microsoft\InputPersonalization"
        if (Test-Path $harvesterPath) {
            Remove-Item -Path "$harvesterPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log 'Кеш підказок набору тексту очищено' -Color DarkGreen
    } catch {
        Write-Log "Не вдалося очистити кеш підказок набору тексту: $(Get-FriendlyErrorMessage $_.Exception.Message)" -Color DarkYellow
    }

    Set-StepStatus -id 10 -status 'success' -result (Get-LocalizedMessage 'layouts_set_result' @('uk-UA', $secondaryLanguageTag))
    Write-Log (Get-LocalizedMessage 'layout_cleanup_completed' @('uk-UA', $secondaryLanguageTag)) -Color DarkGreen
} catch {
    Set-StepStatus -id 10 -status 'skipped' -result (Get-LocalizedMessage 'status_error')
    Add-StepIssue -id 10 -name (Get-LocalizedMessage 'derussification_layouts') -message (Get-FriendlyErrorMessage $_.Exception.Message)
    Write-Log (Get-LocalizedMessage 'layout_cleanup_error' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
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
$optSuccess = $true
try { Set-ItemProperty -Path 'HKU:\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '80000002' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '510' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '20' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Sound' -Name 'Beep' -Value 'no' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }

try {
    Stop-Service -Name 'FontCache' -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat" -Force -ErrorAction SilentlyContinue
    Start-Service -Name 'FontCache' -ErrorAction SilentlyContinue
    Write-Log (Get-LocalizedMessage 'font_cache_cleaned') -Color DarkGreen
} catch {
    Write-Log (Get-LocalizedMessage 'could_not_clean_font_cache') -Color DarkYellow
}

try {
    Write-Log (Get-LocalizedMessage 'restarting_explorer')
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 1
} catch {
    Write-Log (Get-LocalizedMessage 'could_not_restart_explorer') -Color DarkYellow
}

if ($optSuccess) {
    Set-StepStatus -id 11 -status 'success' -result (Get-LocalizedMessage 'status_applied_restart')
    Write-Log (Get-LocalizedMessage 'optimizations_completed') -Color DarkGreen
} else {
    Set-StepStatus -id 11 -status 'skipped' -result (Get-LocalizedMessage 'status_partial')
    Add-StepIssue -id 11 -name (Get-LocalizedMessage 'optimizations_restart') -message 'Частину оптимізацій реєстру не вдалося застосувати'
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
    $checks = New-Object System.Collections.ArrayList
    try {
        $sysLocale = (Get-WinSystemLocale -ErrorAction SilentlyContinue).Name
        [void]$checks.Add(@{ Name = 'Системна локаль'; Ok = ($sysLocale -eq 'uk-UA'); Detail = $sysLocale })
        $uiLang = (Get-WinUILanguageOverride -ErrorAction SilentlyContinue).Name
        [void]$checks.Add(@{ Name = 'Мова інтерфейсу'; Ok = ($uiLang -eq 'uk-UA'); Detail = $uiLang })
        $culture = (Get-Culture).Name
        [void]$checks.Add(@{ Name = 'Регіональний формат'; Ok = ($culture -eq 'uk-UA'); Detail = $culture })
        $llCheck = Get-WinUserLanguageList
        $hasUk = [bool]($llCheck | Where-Object { $_.LanguageTag -eq 'uk-UA' })
        $hasRu = [bool]($llCheck | Where-Object { $_.LanguageTag -match 'ru' })
        [void]$checks.Add(@{ Name = 'Розкладка uk-UA присутня'; Ok = $hasUk; Detail = if ($hasUk) { 'так' } else { 'ні' } })
        [void]$checks.Add(@{ Name = 'Розкладку ru видалено'; Ok = (-not $hasRu); Detail = if ($hasRu) { 'ще є' } else { 'видалено' } })
        $geoId = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
        [void]$checks.Add(@{ Name = 'Регіон розташування'; Ok = ($geoId -eq 240); Detail = "GeoId=$geoId" })

        foreach ($c in $checks) {
            $mark = if ($c.Ok) { 'OK' } else { 'УВАГА' }
            $color = if ($c.Ok) { 'DarkGreen' } else { 'DarkYellow' }
            Write-Log "  [$mark] $($c.Name): $($c.Detail)" -Color $color
        }
        $passCount = ($checks | Where-Object { $_.Ok }).Count
        $totalCount = $checks.Count
        if ($passCount -eq $totalCount) {
            Set-StepStatus -id 12 -status 'success' -result "$passCount/$totalCount OK"
        } else {
            Set-StepStatus -id 12 -status 'skipped' -result "$passCount/$totalCount OK"
            Add-StepIssue -id 12 -name 'Перевірка результату' -message "Не всі перевірки пройдені: $passCount/$totalCount"
        }
    } catch {
        Set-StepStatus -id 12 -status 'skipped' -result 'Помилка перевірки'
        Write-Log "Не вдалося виконати перевірку результату: $(Get-FriendlyErrorMessage $_.Exception.Message)" -Color DarkYellow
    }
}
#endregion

# === Completion ===
try {
    if ($global:UkrainizatorMutex) {
        $global:UkrainizatorMutex.ReleaseMutex()
        $global:UkrainizatorMutex.Dispose()
    }
} catch {}

Show-ProgressBar -Percent 100 -Label (Get-LocalizedMessage 'all_done')

try {
    [Console]::Beep(523, 150)
    [Console]::Beep(659, 150)
    [Console]::Beep(784, 150)
    [Console]::Beep(1046, 300)
} catch {}

Clear-InfoPanel
Show-CompletionBanner

if ($global:FailedSteps.Count -gt 0) {
    $issueLines = @("Завершено з $($global:FailedSteps.Count) непринциповими зауваженнями (див. лог):")
    $issueLines += ($global:FailedSteps | ForEach-Object { "  • $($_.Name): $($_.Message)" })
    Set-InfoPanel -Style 'Warning' -Lines $issueLines
    Write-Host ''
    Start-Sleep -Seconds 3
}

if ($WhatIf) {
    Set-InfoPanel -Lines @('Це був попередній перегляд (-WhatIf) - жодних реальних змін внесено не було.', 'Запустіть без -WhatIf, щоб застосувати.')
    Write-Log '[WhatIf] Завершено без застосування змін' -Color DarkYellow
    Restore-Console
    Write-Host ''
    Write-Host '  Натисніть будь-яку клавішу, щоб завершити...' -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
} elseif ($NoRebootPrompt) {
    Write-Log 'Auto reboot via NoRebootPrompt (з можливістю скасувати)' -Color DarkGreen
    $proceed = Show-CountdownReboot -Seconds 5
    if ($proceed) {
        Restore-Console
        Restart-Computer
    } else {
        Set-InfoPanel -Style 'Warning' -Lines @('Перезавантаження скасовано.', (Get-LocalizedMessage 'dont_forget_reboot'))
        Write-Log 'Автоматичне перезавантаження скасовано користувачем' -Color DarkYellow
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
            Set-InfoPanel -Style 'Warning' -Lines @('Перезавантаження скасовано.', (Get-LocalizedMessage 'dont_forget_reboot'))
            Write-Log 'Перезавантаження скасовано користувачем під час відліку' -Color DarkYellow
            Restore-Console
            Write-Host ''
            Write-Host '  Натисніть будь-яку клавішу, щоб завершити...' -ForegroundColor Gray
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
        Write-Host '  Натисніть будь-яку клавішу, щоб завершити...' -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    }
}
