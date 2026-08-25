# modules/UI.psm1
# ============================================================
# Ukrainizator - Modern UI Engine (ANSI / VT)
# Палітра, градієнти, кадр малюється повністю (Show-Frame),
# спінери, статуси кроків, лог, промпти, банер завершення.
# ============================================================

$ESC = [char]27

$script:Palette = @{
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

function Clear-UiScreen {
    # Повне очищення екрана ANSI-шляхом (використовується при бутстрапі).
    if ($global:UseAnsi) { Write-Raw "$ESC[2J$ESC[H" }
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
    # Орієнтуємось виключно на реальний результат спроби увімкнути
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
    Write-Host ("  {0}  УКРАЇНІЗАТОР  v{1}" -f [char]0x2502, $global:ScriptVersion) -ForegroundColor White
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
    $titleRight = "$($P.Dim)v$($global:ScriptVersion)$($P.Reset) "
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
    # Повне очищення екрана перед кожним кадром прибирає залежність від
    # неточної ширини вікна на старті - результат завжди коректний.
    [void]$sb.Append("$ESC[2J$ESC[H")
    [void]$sb.Append(($lines -join "`n"))
    Write-Raw $sb.ToString()
    $global:AnsiLinesDrawn = $lines.Count
}

function Set-StepStatus {
    param([int]$id, [string]$status, [string]$result = '', [string]$details = '')
    $step = $global:steps | Where-Object { $_.id -eq $id }
    if (-not $step) { return }
    $step.status = $status
    $step.result = $result
    $step.details = $details

    if ($status -eq 'success') {
        Invoke-Sound -Type 'StepSuccess' -Variant $id
    } elseif ($status -eq 'skipped') {
        Invoke-Sound -Type 'StepSkipped'
    }

    if ($global:UseAnsi) {
        Show-Frame
        return
    }

    # Плаский режим: пропускаємо проміжний стан 'running', друкуємо лише
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
    Add-Content -Path $global:LogFile -Value $logMessage -Encoding UTF8

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
    Invoke-Sound -Type 'StepError'
    Set-InfoPanel -Lines @($Message) -Style 'Error'
    Write-Log "$(Get-LocalizedMessage 'error_log_prefix')$Message" -Color Red
    if ($global:UseAnsi) { Write-Raw "`n`n" }
    Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    Restore-Console
    exit 1
}

function Show-CompletionBanner {
    $elapsed = (Get-Date) - $global:StartTime
    $P = $Palette
    $global:UIState.Footer = @(
        "  $($P.Green)$($P.Bold)$([char]0x2713) $(Get-LocalizedMessage 'all_done')$($P.Reset)",
        "  $($P.Dim)$(Get-LocalizedMessage 'time_elapsed') $($elapsed.Minutes)m $($elapsed.Seconds)s$($P.Reset)",
        "  $($P.Dim)$(Get-LocalizedMessage 'log_file') $global:LogFile$($P.Reset)"
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
    Write-Host ("  {0}  {1} {2}" -f [char]0x2502, (Get-LocalizedMessage 'log_file'), $global:LogFile) -ForegroundColor DarkGray
    Write-Host "  $bot" -ForegroundColor Green
}

function Show-CountdownReboot {
    # Відлік перед перезавантаженням з можливістю скасувати будь-якою клавішею.
    param([int]$Seconds = 15)
    for ($s = $Seconds; $s -gt 0; $s--) {
        Set-InfoPanel -Lines @((Get-LocalizedMessage 'rebooting_countdown' (Get-LocalizedMessage 'rebooting') $s))
        Invoke-Sound -Type 'CountdownTick' -Variant $s
        try {
            if ([Console]::KeyAvailable) {
                [Console]::ReadKey($true) | Out-Null
                Invoke-Sound -Type 'Cancel'
                return $false
            }
        } catch {}
        Start-Sleep -Seconds 1
    }
    return $true
}




