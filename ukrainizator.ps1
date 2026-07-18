# Ukrainizator v4.0.0
# ============================================================
# Windows Ukrainian language setup script (Professional UI)
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

try {
    cmd /c chcp 65001 | Out-Null
} catch {}

try {
    $consolePath = 'HKCU:\Console'
    if (Test-Path $consolePath) {
        Set-ItemProperty -Path $consolePath -Name 'FaceName' -Value 'Lucida Console' -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $consolePath -Name 'FontSize' -Value 0x100000 -ErrorAction SilentlyContinue
    }
} catch {}

#region === Settings & State ===
$scriptVersion = '4.0.0'
Get-ChildItem -Path $PSScriptRoot -Filter 'Ukrainizator_*.log' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
$logFile = Join-Path $PSScriptRoot "Ukrainizator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$startTime = Get-Date

$global:steps = @(
    @{ id = 1;  name = 'Administrator rights';      status = 'pending'; result = '' },
    @{ id = 2;  name = 'PowerShell version';         status = 'pending'; result = '' },
    @{ id = 3;  name = 'Internet connectivity';      status = 'pending'; result = '' },
    @{ id = 4;  name = 'Confirmation';               status = 'pending'; result = '' },
    @{ id = 5;  name = 'Restore point';              status = 'pending'; result = '' },
    @{ id = 6;  name = 'Installation mode';          status = 'pending'; result = '' },
    @{ id = 7;  name = 'System modules';             status = 'pending'; result = '' },
    @{ id = 8;  name = 'uk-UA language pack';        status = 'pending'; result = '' },
    @{ id = 9;  name = 'Interface language';         status = 'pending'; result = '' },
    @{ id = 10; name = 'Regional standards';         status = 'pending'; result = '' },
    @{ id = 11; name = 'Layout cleanup';             status = 'pending'; result = '' },
    @{ id = 12; name = 'Optimizations and restart';   status = 'pending'; result = '' }
)

$global:uiHeaderHeight = 11
$global:uiListHeight = 14
#endregion

#region === UI Functions ===
function Clear-ActivityZone {
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
    [Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 1)
    Write-Host "  $logMessage" -ForegroundColor $Color
}

function Set-StepStatus {
    param([int]$id, [string]$status, [string]$result = '')
    $step = $global:steps | Where-Object { $_.id -eq $id }
    $step.status = $status
    $step.result = $result

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

        $resText = ''
        if ($step.result) {
            $resText = ' -> ' + $step.result
        }

        Write-Host ("{0} {1}. {2}{3}" -f $marker, $step.id, $step.name, $resText) -ForegroundColor $color
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
    Write-Host '  Installing Ukrainian language in Windows' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "Log: $logFile" -ForegroundColor Gray
    Write-Host ''
}

function Write-ErrorExit {
    param([string]$Message, [int]$stepId)
    Set-StepStatus -id $stepId -status 'error' -result 'Error'
    [Console]::Beep(300,300)
    Clear-ActivityZone
    Write-Host ''
    Write-Host "  [!] $Message" -ForegroundColor Red
    Write-Log "ERROR: $Message" -Color Red
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor Gray
    $null = [Console]::ReadKey($true)
    exit 1
}

function Read-HostWithDefault {
    param([string]$Default = 'Y')
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
        if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
        return $result
    }
}
#endregion

# === Start ===
Show-FlagHeader
Update-UI
Write-Log "Starting Ukrainizator v$scriptVersion"

#region === 1. Privilege Check ===
Set-StepStatus -id 1 -status 'running'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-ErrorExit 'Administrator rights are required!' 1
}
Set-StepStatus -id 1 -status 'success' -result 'OK'
Write-Log 'Administrator rights confirmed' -Color Green
#endregion

#region === 2. PowerShell Version ===
Set-StepStatus -id 2 -status 'running'
Show-ProgressBar -Percent 10 -Label 'PS version'
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-ErrorExit 'PowerShell 5.1+ is required' 2
}
Set-StepStatus -id 2 -status 'success' -result "v$($PSVersionTable.PSVersion)"
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" -Color Green
#endregion

#region === 3. Internet ===
Set-StepStatus -id 3 -status 'running'
Show-ProgressBar -Percent 20 -Label 'Network'
Write-Log 'Checking network connectivity...'
$online = $false
try {
    $online = Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet -ErrorAction Stop
} catch {
    try { Invoke-WebRequest -Uri 'https://www.microsoft.com' -UseBasicParsing -ErrorAction Stop | Out-Null; $online = $true } catch {}
}
if (-not $online) {
    Write-ErrorExit 'Internet is unavailable!' 3
}
Set-StepStatus -id 3 -status 'success' -result 'Online'
Write-Log 'Internet is available' -Color Green
#endregion

#region === 4. Warning ===
Set-StepStatus -id 4 -status 'running'
Show-ProgressBar -Percent 30 -Label 'Warning'
Clear-ActivityZone
[Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 2)
Write-Host '  WARNING: This script changes system language and layouts.' -ForegroundColor Red
Write-Host '  A reboot will be required after completion.' -ForegroundColor Red
Write-Host '  RECOMMENDED: CREATE A RESTORE POINT.' -ForegroundColor Yellow
Write-Host ''
if ($Silent) {
    Set-StepStatus -id 4 -status 'success' -result 'Auto'
    Write-Log 'Confirmation skipped in Silent mode' -Color Green
} else {
    Write-Host '  Continue? (Y/N): ' -NoNewline -ForegroundColor Yellow
    $confirm = Read-HostWithDefault -Default 'Y'
    if ($confirm -notin @('Y','y','Yes','YES','ok','OK','yep')) {
        Set-StepStatus -id 4 -status 'error' -result 'Cancelled'
        Write-Log 'Cancelled by user' -Color Red
        exit 1
    }
    Set-StepStatus -id 4 -status 'success' -result 'Confirmed'
    Write-Log 'User confirmed execution' -Color Green
}
#endregion

#region === 5. Restore Point ===
Set-StepStatus -id 5 -status 'running'
Show-ProgressBar -Percent 35 -Label 'Restore point'
Write-Log 'Creating restore point...'
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description "Before running Ukrainizator" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Set-StepStatus -id 5 -status 'success' -result 'Created'
    Write-Log 'System restore point created successfully' -Color Green
} catch {
    if ($_.Exception.Message -match "24") {
        Set-StepStatus -id 5 -status 'success' -result 'Already created (<24h)'
        Write-Log 'Restore point was already created less than 24 hours ago' -Color Green
    } else {
        Set-StepStatus -id 5 -status 'skipped' -result 'Skipped'
        Write-Log "Restore point creation failed: $($_.Exception.Message)" -Color Yellow
    }
}
#endregion

#region === 6. Installation Mode Selection ===
Set-StepStatus -id 6 -status 'running'
Show-ProgressBar -Percent 40 -Label 'Mode'
Clear-ActivityZone
[Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 2)
if ($Silent) {
    $installMode = $Mode
    $modeText = if ($Mode -eq 'All') { 'All users (auto)' } else { 'Current user (auto)' }
    Set-StepStatus -id 6 -status 'success' -result $modeText
    Write-Log "Silent mode: selected $modeText" -Color Green
} else {
    Write-Host '  Apply to:' -ForegroundColor Yellow
    Write-Host '    [A] all users (recommended)' -ForegroundColor Cyan
    Write-Host '    [C] current user only' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Your choice (A/C): ' -NoNewline -ForegroundColor Yellow
    $installMode = Read-HostWithDefault -Default 'A'
    if ($installMode -notin @('A','a','All','ALL')) {
        $installMode = 'Current'
        $modeText = 'Current user'
    } else {
        $installMode = 'All'
        $modeText = 'All users'
    }
    Set-StepStatus -id 6 -status 'success' -result $modeText
    Write-Log "Selected mode: $modeText" -Color Green
}
#endregion

#region === 7. Modules ===
Set-StepStatus -id 7 -status 'running'
Show-ProgressBar -Percent 50 -Label 'Modules'
Import-Module LanguagePackManagement -ErrorAction SilentlyContinue
if (-not (Get-Module -ListAvailable -Name LanguagePackManagement)) {
    Write-ErrorExit 'LanguagePackManagement module is not available.' 7
}
Set-StepStatus -id 7 -status 'success' -result 'Loaded'
Write-Log 'LanguagePackManagement module loaded' -Color Green
#endregion

#region === 8. Language Pack ===
Set-StepStatus -id 8 -status 'running'
Show-ProgressBar -Percent 60 -Label 'Language pack'
$ukUaInstalled = $false
if ((Get-InstalledLanguage | Out-String) -match 'uk-UA') { $ukUaInstalled = $true }
if (-not $ukUaInstalled) { if ((Get-WinUserLanguageList | Out-String) -match 'uk-UA') { $ukUaInstalled = $true } }

if ($ukUaInstalled) {
    Set-StepStatus -id 8 -status 'skipped' -result 'Already installed'
    Write-Log 'uk-UA is already installed, skipping' -Color Yellow
} else {
    Write-Log 'Installing uk-UA... (this may take some time)' -Color Yellow
    try {
        Install-Language -Language 'uk-UA' -CopyToSettings -ExcludeFeatures -ErrorAction Stop
        $ukUaInstalled = $false
        for ($i = 1; $i -le 15; $i++) {
            Start-Sleep -Seconds 3
            if ((Get-InstalledLanguage | Out-String) -match 'uk-UA') { $ukUaInstalled = $true; break }
            if ((Get-WinUserLanguageList | Out-String) -match 'uk-UA') { $ukUaInstalled = $true; break }
        }
        if (-not $ukUaInstalled) { Write-ErrorExit 'uk-UA was not found after installation.' 8 }
        Set-StepStatus -id 8 -status 'success' -result 'Installed'
        Write-Log 'uk-UA installed successfully' -Color Green
    } catch {
        Write-ErrorExit "Installation error: $($_.Exception.Message)" 8
    }
}
#endregion

#region === 9. Interface ===
Set-StepStatus -id 9 -status 'running'
Show-ProgressBar -Percent 70 -Label 'Interface'
try {
    Set-WinUILanguageOverride -Language 'uk-UA' -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value '0422' -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value '0422' -ErrorAction Stop

    if ($installMode -eq 'All') {
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
            Write-Log 'Copied settings to WelcomeScreen + NewUser' -Color Green
        } catch {
            Write-Log 'Copying international settings failed (Win10?)' -Color Yellow
        }
    }
    Set-StepStatus -id 9 -status 'success' -result 'uk-UA set'
    Write-Log 'Interface language set' -Color Green
} catch {
    Set-StepStatus -id 9 -status 'skipped' -result 'Partial'
    Write-Log "Interface language error: $($_.Exception.Message)" -Color Yellow
}
#endregion

#region === 10. Regional Formats ===
Set-StepStatus -id 10 -status 'running'
Show-ProgressBar -Percent 80 -Label 'Regional formats'
try {
    Set-Culture -CultureInfo 'uk-UA' -ErrorAction Stop
    Set-WinSystemLocale -SystemLocale 'uk-UA' -ErrorAction Stop
    Set-WinHomeLocation -GeoId 240 -ErrorAction Stop
    Set-StepStatus -id 10 -status 'success' -result 'uk-UA (Ukraine)'
    Write-Log 'Regional standards set to uk-UA' -Color Green
} catch {
    Set-StepStatus -id 10 -status 'skipped' -result 'Partial'
    Write-Log "Regional formats error: $($_.Exception.Message)" -Color Yellow
}
#endregion

#region === 11. Derussification & Layouts ===
Set-StepStatus -id 11 -status 'running'
Show-ProgressBar -Percent 90 -Label 'Layouts'
try {
    $list = Get-WinUserLanguageList
    $ruLanguages = $list | Where-Object { $_.LanguageTag -match 'ru' }
    foreach ($ruLang in $ruLanguages) {
        $list.Remove($ruLang)
        Write-Log "Removed Russian language from list: $($ruLang.LanguageTag)" -Color Yellow
    }

    $ll = New-WinUserLanguageList -Language 'uk-UA'
    $ll.Add('en-US')

    $uk = $ll | Where-Object { $_.LanguageTag -eq 'uk-UA' }
    $uk.InputMethodTips.Clear()
    $uk.InputMethodTips.Add('0422:00000422')
    $en = $ll | Where-Object { $_.LanguageTag -eq 'en-US' }
    $en.InputMethodTips.Clear()
    $en.InputMethodTips.Add('0409:00000409')

    Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction Stop

    $preloadPath = 'HKCU:\Keyboard Layout\Preload'
    if (Test-Path $preloadPath) {
        $preloads = Get-ItemProperty -Path $preloadPath
        foreach ($prop in $preloads.PSObject.Properties) {
            if ($prop.Value -eq '00000419') {
                Remove-ItemProperty -Path $preloadPath -Name $prop.Name -Force -ErrorAction SilentlyContinue
                Write-Log 'Removed Russian layout from keyboard preload' -Color Yellow
            }
        }
    }

    $togglePath = 'HKCU:\Keyboard Layout\Toggle'
    if (-not (Test-Path $togglePath)) { New-Item -Path $togglePath -Force | Out-Null }
    Set-ItemProperty -Path $togglePath -Name 'Hotkey' -Value 1 -ErrorAction Stop

    Set-StepStatus -id 11 -status 'success' -result 'UKR+ENG (no RU)'
    Write-Log 'Layout cleanup completed, layouts set (Shift+Alt)' -Color Green
} catch {
    Set-StepStatus -id 11 -status 'skipped' -result 'Error'
    Write-Log "Layout cleanup error: $($_.Exception.Message)" -Color Yellow
}
#endregion

#region === 12. Optimizations & Explorer Restart ===
Set-StepStatus -id 12 -status 'running'
Show-ProgressBar -Percent 95 -Label 'Optimization'
$optSuccess = $true
try { Set-ItemProperty -Path 'HKU:\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '80000002' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '510' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '20' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }
try { Set-ItemProperty -Path 'HKCU:\Control Panel\Sound' -Name 'Beep' -Value 'no' -ErrorAction SilentlyContinue } catch { $optSuccess = $false }

try {
    Stop-Service -Name 'FontCache' -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:windir\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat" -Force -ErrorAction SilentlyContinue
    Start-Service -Name 'FontCache' -ErrorAction SilentlyContinue
    Write-Log 'Font cache cleaned' -Color Green
} catch {
    Write-Log 'Could not clean font cache, skipped' -Color Yellow
}

try {
    Write-Log 'Restarting explorer.exe...'
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 1
} catch {
    Write-Log 'Could not restart Explorer' -Color Yellow
}

if ($optSuccess) {
    Set-StepStatus -id 12 -status 'success' -result 'Applied + Restart'
    Write-Log 'Optimizations and Explorer restart completed' -Color Green
} else {
    Set-StepStatus -id 12 -status 'skipped' -result 'Partial'
    Write-Log 'Some optimizations were not applied' -Color Yellow
}
#endregion

# === Completion ===
Show-ProgressBar -Percent 100 -Label 'Done!'

[Console]::Beep(523, 150)
[Console]::Beep(659, 150)
[Console]::Beep(784, 150)
[Console]::Beep(1046, 300)

Clear-ActivityZone
[Console]::SetCursorPosition(0, $global:uiHeaderHeight + $global:uiListHeight + 3)
Write-Host '============================================' -ForegroundColor Green
Write-Host '   ALL DONE!' -ForegroundColor Yellow
Write-Host '============================================' -ForegroundColor Green
$elapsed = (Get-Date) - $startTime
Write-Host "Time: $($elapsed.Minutes)m $($elapsed.Seconds)s" -ForegroundColor Gray
Write-Host "Log: $logFile" -ForegroundColor Gray
Write-Host ''

if ($NoRebootPrompt) {
    Write-Host '  Rebooting...' -ForegroundColor Green
    Write-Log 'Auto reboot via NoRebootPrompt' -Color Green
    Start-Sleep -Seconds 2
    Restart-Computer
} else {
    Write-Host 'Reboot now? (Y/N): ' -NoNewline -ForegroundColor Yellow
    $reboot = Read-HostWithDefault -Default 'Y'
    if ($reboot -in @('Y','y','Yes','YES','ok','OK','yep')) {
        Write-Host '  Rebooting... See you soon!' -ForegroundColor Green
        Write-Log 'Reboot requested' -Color Green
        Start-Sleep -Seconds 2
        Restart-Computer
    } else {
        Write-Host "  [i] Don't forget to reboot your computer later." -ForegroundColor Yellow
        Write-Host '  Thank you for using Ukrainizator!' -ForegroundColor Cyan
        Write-Log 'User declined reboot' -Color Yellow
        pause
    }
}