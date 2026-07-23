# Ukrainizator v4.2.0
# ============================================================
# Windows Ukrainian language setup script (Modern UI)
# ============================================================

param(
    [switch]$Silent,
    [ValidateSet('All', 'Current')]
    [string]$Mode = 'All',
    [switch]$NoRebootPrompt
)

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
#endregion

#region === Settings & State ===
$scriptVersion = '4.2.0'
Get-ChildItem -Path $PSScriptRoot -Filter 'Ukrainizator_*.log' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
$logFile = Join-Path $PSScriptRoot "Ukrainizator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$startTime = Get-Date
$global:steps = @()
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
    Reset  = "$ESC[0m"
    Bold   = "$ESC[1m"
    Dim    = "$ESC[2m"
    Blue   = "$ESC[38;5;33m"
    Yellow = "$ESC[38;5;221m"
    Green  = "$ESC[38;5;78m"
    Red    = "$ESC[38;5;203m"
    Cyan   = "$ESC[38;5;51m"
    Gray   = "$ESC[38;5;244m"
    White  = "$ESC[38;5;231m"
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
        'skipped' { return @{ Char = [string][char]0x25CF; Color = 'DarkYellow' } }
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

function Build-Frame {
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
    $subtitle = " $($P.Cyan)Встановлення української мови в Windows$($P.Reset)"

    $lines.Add("$($P.Blue)$top$($P.Reset)")
    $lines.Add("$($P.Blue)$([char]0x2502)$($P.Reset)" + (Set-PaddedLine $titleLine ($w - 2)) + "$($P.Blue)$([char]0x2502)$($P.Reset)")
    $lines.Add("$($P.Blue)$([char]0x2502)$($P.Reset)" + (Set-PaddedLine $subtitle ($w - 2)) + "$($P.Blue)$([char]0x2502)$($P.Reset)")
    $lines.Add("$($P.Blue)$bot$($P.Reset)")
    $lines.Add('')

    # --- Steps ---
    foreach ($step in $global:steps) {
        $icon = Get-StepIcon $step
        $idText = $step.id.ToString().PadLeft(2)
        $nameRaw = " $idText.  $($step.name)"
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
    $barColor = $P.Cyan
    if ($pct -ge 100) { $barColor = $P.Green }
    $bar = "$barColor" + ([string]([char]0x2588) * $filled) + "$($P.Dim)" + ([string]([char]0x2591) * $empty) + "$($P.Reset)"
    $pctText = "$($pct.ToString().PadLeft(3))%"
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

function Render-UI {
    if (-not $global:UseAnsi) { return }
    $lines = Build-Frame
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
        Render-UI
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
    if ($global:UseAnsi) { Render-UI }
}

function Set-InfoPanel {
    param([string[]]$Lines, [string]$Style = 'Normal')
    $global:UIState.InfoLines = $Lines
    $global:UIState.InfoStyle = $Style
    if ($global:UseAnsi) {
        Render-UI
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
    if ($global:UseAnsi) { Render-UI }
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
        Render-UI
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
        Render-UI
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
        Render-UI
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
    @{ id = 11; name = (Get-LocalizedMessage 'optimizations_restart');      status = 'pending'; result = ''; details = '' }
)

Render-UI
Write-Log "$(Get-LocalizedMessage 'starting_ukrainizator') v$scriptVersion"

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
        Write-Log "$(Get-LocalizedMessage 'restore_point_failed')$($_.Exception.Message)" -Color DarkYellow
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
if (-not (Get-Module -ListAvailable -Name LanguagePackManagement)) {
    Write-ErrorExit (Get-LocalizedMessage 'languagemanagement_not_available') 6
}
Set-StepStatus -id 6 -status 'success' -result (Get-LocalizedMessage 'loaded')
Write-Log (Get-LocalizedMessage 'languagemanagement_loaded') -Color DarkGreen
#endregion

#region === 7. Language Pack ===
Set-StepStatus -id 7 -status 'running'
Show-ProgressBar -Percent 60 -Label (Get-LocalizedMessage 'language_pack_installation')
$targetLanguageTag = 'uk-UA'
$targetLanguageInstalled = $false
if ((Get-InstalledLanguage | Out-String) -match $targetLanguageTag) { $targetLanguageInstalled = $true }
if (-not $targetLanguageInstalled) { if ((Get-WinUserLanguageList | Out-String) -match $targetLanguageTag) { $targetLanguageInstalled = $true } }

if ($targetLanguageInstalled) {
    Set-StepStatus -id 7 -status 'skipped' -result (Get-LocalizedMessage 'already_installed')
    Write-Log (Get-LocalizedMessage 'language_already_installed' $targetLanguageTag) -Color DarkYellow
} else {
    Write-Log (Get-LocalizedMessage 'installing_language' $targetLanguageTag) -Color DarkYellow
    try {
        Install-Language -Language $targetLanguageTag -CopyToSettings -ExcludeFeatures -ErrorAction Stop
        $targetLanguageInstalled = $false
        for ($i = 1; $i -le 15; $i++) {
            Start-Sleep -Seconds 3
            $global:UIState.SpinnerFrame++
            if ($global:UseAnsi) { Render-UI }
            if ((Get-InstalledLanguage | Out-String) -match $targetLanguageTag) { $targetLanguageInstalled = $true; break }
            if ((Get-WinUserLanguageList | Out-String) -match $targetLanguageTag) { $targetLanguageInstalled = $true; break }
        }
        if (-not $targetLanguageInstalled) { Write-ErrorExit (Get-LocalizedMessage 'language_not_found_after_install' $targetLanguageTag) 7 }
        Set-StepStatus -id 7 -status 'success' -result (Get-LocalizedMessage 'installed')
        Write-Log (Get-LocalizedMessage 'language_installed_successfully' $targetLanguageTag) -Color DarkGreen
    } catch {
        Write-ErrorExit (Get-LocalizedMessage 'installation_error' $_.Exception.Message) 7
    }
}
#endregion

#region === 8. Interface ===
Set-StepStatus -id 8 -status 'running'
Show-ProgressBar -Percent 70 -Label (Get-LocalizedMessage 'interface_label')
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
    Write-Log (Get-LocalizedMessage 'interface_language_error' $_.Exception.Message) -Color DarkYellow
}
#endregion

#region === 9. Regional Formats ===
Set-StepStatus -id 9 -status 'running'
Show-ProgressBar -Percent 80 -Label (Get-LocalizedMessage 'regional_formats_label')
try {
    Set-Culture -CultureInfo 'uk-UA' -ErrorAction Stop
    Set-WinSystemLocale -SystemLocale 'uk-UA' -ErrorAction Stop
    $geoId = 240
    Set-WinHomeLocation -GeoId $geoId -ErrorAction Stop
    Set-StepStatus -id 9 -status 'success' -result (Get-LocalizedMessage 'regional_formats_set_result' 'uk-UA' 'uk-UA')
    Write-Log (Get-LocalizedMessage 'regional_standards_set' 'uk-UA') -Color DarkGreen
} catch {
    Set-StepStatus -id 9 -status 'skipped' -result (Get-LocalizedMessage 'status_partial')
    Write-Log (Get-LocalizedMessage 'regional_formats_error' $_.Exception.Message) -Color DarkYellow
}
#endregion

#region === 10. Derussification & Layouts ===
Set-StepStatus -id 10 -status 'running'
Show-ProgressBar -Percent 90 -Label (Get-LocalizedMessage 'layouts_label')
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

    Set-StepStatus -id 10 -status 'success' -result (Get-LocalizedMessage 'layouts_set_result' @('uk-UA', $secondaryLanguageTag))
    Write-Log (Get-LocalizedMessage 'layout_cleanup_completed' @('uk-UA', $secondaryLanguageTag)) -Color DarkGreen
} catch {
    Set-StepStatus -id 10 -status 'skipped' -result (Get-LocalizedMessage 'status_error')
    Write-Log (Get-LocalizedMessage 'layout_cleanup_error' $_.Exception.Message) -Color DarkYellow
}
#endregion

#region === 11. Optimizations & Explorer Restart ===
Set-StepStatus -id 11 -status 'running'
Show-ProgressBar -Percent 95 -Label (Get-LocalizedMessage 'optimization_label')
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
    Write-Log (Get-LocalizedMessage 'some_optimizations_not_applied') -Color DarkYellow
}
#endregion

# === Completion ===
Show-ProgressBar -Percent 100 -Label (Get-LocalizedMessage 'all_done')

try {
    [Console]::Beep(523, 150)
    [Console]::Beep(659, 150)
    [Console]::Beep(784, 150)
    [Console]::Beep(1046, 300)
} catch {}

Clear-InfoPanel
Show-CompletionBanner

if ($NoRebootPrompt) {
    Set-InfoPanel -Lines @((Get-LocalizedMessage 'rebooting'))
    Write-Log 'Auto reboot via NoRebootPrompt' -Color DarkGreen
    Start-Sleep -Seconds 2
    Restore-Console
    Restart-Computer
} else {
    $reboot = Show-Prompt -Text (Get-LocalizedMessage 'reboot_now_prompt') -Default 'Y'
    if ($reboot -in (Get-LocalizedMessage 'reboot_yes_answers')) {
        Set-InfoPanel -Lines @("$(Get-LocalizedMessage 'rebooting')$(Get-LocalizedMessage 'see_you_soon')")
        Write-Log (Get-LocalizedMessage 'reboot_requested') -Color DarkGreen
        Start-Sleep -Seconds 2
        Restore-Console
        Restart-Computer
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
