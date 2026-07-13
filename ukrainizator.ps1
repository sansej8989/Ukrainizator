# Ukrainizator v3.0.0
# ============================================================
# Vstanovlennia ukrainskoi movy dlia Windows
# ============================================================

# Vstanovlennia UTF-8 dlia korektnoho vidobrazhennia
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

#region === Settings ===
$scriptVersion = '3.0.0'
Get-ChildItem -Path $PSScriptRoot -Filter 'Ukrainizator_*.log' -File | Remove-Item -Force
$logFile = Join-Path $PSScriptRoot "Ukrainizator_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
    $filled = [int][math]::Floor($Percent / 100 * $barSize)
    $empty = [int]($barSize - $filled)
    $bar = ([string][char]9608 * $filled) + ([string][char]9617 * $empty)
    if ($Label) { Write-Host "  $bar  $Percent%  $Label" -ForegroundColor Yellow }
    else { Write-Host "  $bar  $Percent%" -ForegroundColor Yellow }
    Write-Host ""
}

function Write-ErrorExit {
    param([string]$Message)
    [console]::beep(800,300)
    Write-Host "  [!] $Message" -ForegroundColor Red
    Write-Log "ERROR: $Message" -Color Red
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
    Write-Host '  UKRAINIZATOR  v3.0.0' -ForegroundColor Yellow
    Write-Host '  Vstanovlennia ukrainskoi movy v Windows' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "Log: $logFile" -ForegroundColor Gray
}
#endregion

#region === Header ===
Show-FlagHeader
Write-Log "Zapusk Ukrainizator v$scriptVersion"
#endregion

#region === 1. Privilege Check ===
Show-FlagHeader
Write-Step '*** Krok 1/10 ***' 'Perevirka prav administratora'
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-ErrorExit 'Potribni prava administratora! Bud laska, zapustit vid imeni administratora.'
}
Write-Host '  [OK] Prava administratora pidtverdzheno.' -ForegroundColor Green
Write-Log 'Prava administratora pidtverdzheno' -Color Green
#endregion

#region === 2. PowerShell Version ===
Show-FlagHeader
Write-Step '*** Krok 2/10 ***' 'Perevirka versii PowerShell'
Show-ProgressBar -Percent 10 -Label 'PowerShell'
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-ErrorExit "Potriben PowerShell 5.1+ (potochna versiya: $($PSVersionTable.PSVersion))"
}
Write-Host "  [OK] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
Write-Log "Versiya PowerShell: $($PSVersionTable.PSVersion)" -Color Green
#endregion

#region === 3. Internet ===
Show-FlagHeader
Write-Step '*** Krok 3/10 ***' 'Perevirka pidkliuchennia do internetu'
Show-ProgressBar -Percent 20 -Label 'Internet'
Write-Host '  Perevirka...' -NoNewline
$online = $false
try {
    $online = Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet -ErrorAction Stop
} catch {
    try { Invoke-WebRequest -Uri 'https://www.microsoft.com' -UseBasicParsing -ErrorAction Stop | Out-Null; $online = $true } catch {}
}
if (-not $online) {
Write-ErrorExit "Internet nedostupnyi! Pidkliuchennia potribne dlia zavantazhennia movnoho paketa."
}
Write-Host ' [OK]' -ForegroundColor Green
Write-Host '  [OK] Internet dostupnyi.' -ForegroundColor Green
Write-Log 'Internet pidtverdzheno' -Color Green
#endregion

#region === 4. Warning ===
Show-FlagHeader
Write-Step '*** Krok 4/10 ***' 'Poperedzhennia'
Show-ProgressBar -Percent 40 -Label 'Poperedzhennia'
Write-Host ''
Write-Host '  UVAGA: Skrypt zminiuie systemnu movu, movu interfeisu' -ForegroundColor Red
Write-Host '  ta rozkladky klaviatury dlia vsikh korystuvachiv.' -ForegroundColor Red
Write-Host '  Pislia zavershennia potribne perezavantazhennia.' -ForegroundColor Red
Write-Host '  REKOMENDUIEMO STVORYTY TOCHKU VIDNOVLENNIA.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Prodovzhyty? (Y/N): ' -NoNewline -ForegroundColor Yellow
$confirm = Read-Host
if ($confirm -notin @('Y','y','Yes','YES','ok','OK','yep')) {
Write-Host '  Skasovano korystuvachem.' -ForegroundColor Red
Write-Log 'Skasovano korystuvachem' -Color Red
    exit 1
}
Write-Host '  [OK] Prodovzhuiemo...' -ForegroundColor Green
Write-Log 'Korystuvach pidtverdhyv vykonannia' -Color Green
#endregion

#region === 5. Installation Mode Selection ===
Show-FlagHeader
Write-Step '*** Krok 5/10 ***' 'Vybir rezhimu vstanovlennia'
Write-Host ''
Write-Host '  Zastosuvaty do:' -ForegroundColor Yellow
Write-Host '    [A] vsikh korystuvachiv (rekomendovano)' -ForegroundColor Cyan
Write-Host '    [C] tilky potochnoho korystuvacha' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Vash vybir (A/C): ' -NoNewline -ForegroundColor Yellow
$installMode = Read-Host
if ($installMode -notin @('A','a','All','ALL')) {
    $installMode = 'Current'
    Write-Host '  [i] Vybrano: tilky potochnyi korystuvach.' -ForegroundColor Gray
    Write-Log 'Vybrano rezhim: tilky potochnyi korystuvach' -Color Gray
} else {
    $installMode = 'All'
    Write-Host '  [OK] Vybrano: vsi korystuvachi.' -ForegroundColor Green
    Write-Log 'Vybrano rezhim: vsi korystuvachi' -Color Green
}
Show-ProgressBar -Percent 45 -Label 'Rezhim vybrano'
#endregion

#region === 6. Modules ===
Show-FlagHeader
Write-Step '*** Krok 6/10 ***' 'Perevirka systemnykh moduliv'
Show-ProgressBar -Percent 55 -Label 'Moduli'
Import-Module LanguagePackManagement -ErrorAction SilentlyContinue
if (-not (Get-Module -ListAvailable -Name LanguagePackManagement)) {
    Write-ErrorExit 'Modul LanguagePackManagement nedostupnyi. Perekonaitesia, shcho systema onovlena.'
}
Write-Host '  [OK] Modul LanguagePackManagement zavantazheno.' -ForegroundColor Green
Write-Log 'Modul LanguagePackManagement zavantazheno' -Color Green
#endregion

#region === 7. Language Pack ===
Show-FlagHeader
Write-Step '*** Krok 7/10 ***' 'Vstanovlennia ukrainskoho movnoho paketa'
Show-ProgressBar -Percent 65 -Label 'Movnyi paket'
$ukUaInstalled = $false
if ((Get-InstalledLanguage | Out-String) -match 'uk-UA') { $ukUaInstalled = $true }
if (-not $ukUaInstalled) { if ((Get-WinUserLanguageList | Out-String) -match 'uk-UA') { $ukUaInstalled = $true } }
if ($ukUaInstalled) {
    Write-Host '  [OK] uk-UA vzhe vstanovleno. Propuskaiemo.' -ForegroundColor Yellow
    Write-Log 'uk-UA vzhe vstanovleno, propuskaiemo' -Color Yellow
    Show-ProgressBar -Percent 70 -Label 'Vzhe vstanovleno'
} else {
    Write-Host '  Vstanovlennia uk-UA...' -ForegroundColor Yellow
    Write-Log 'Pochatok vstanovlennia uk-UA' -Color Yellow
    try {
        Install-Language -Language 'uk-UA' -CopyToSettings -ExcludeFeatures -ErrorAction Stop
        $ukUaInstalled = $false
        for ($i = 1; $i -le 10; $i++) {
            Start-Sleep -Seconds 3
            if ((Get-InstalledLanguage | Out-String) -match 'uk-UA') { $ukUaInstalled = $true; break }
            if ((Get-WinUserLanguageList | Out-String) -match 'uk-UA') { $ukUaInstalled = $true; break }
        }
        if (-not $ukUaInstalled) { Write-ErrorExit 'uk-UA ne znaideno pislia vstanovlennia. Perevirte systemu.' }
        Write-Host '  [OK] Movnyi paket vstanovleno.' -ForegroundColor Green
        Write-Log 'uk-UA vstanovleno uspishno' -Color Green
    } catch { Write-ErrorExit "Pomylka vstanovlennia movy: $($_.Exception.Message)" }
    Show-ProgressBar -Percent 70 -Label 'Vstanovleno'
}
#endregion

#region === 8. Interface ===
Show-FlagHeader
Write-Step '*** Krok 8/10 ***' 'Nalashtuvannia movy interfeisu'
try {
    Set-WinUILanguageOverride -Language 'uk-UA' -ErrorAction Stop
    Write-Host '  [OK] Mova interfeisu vstanovlena (pislia perezavantazhennia).' -ForegroundColor Green
    Write-Log 'Mova interfeisu uk-UA vstanovlena' -Color Green
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value '0422' -ErrorAction Stop
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value '0422' -ErrorAction Stop
    Write-Host '  [OK] Reiestr Nls\Language: Default+InstallLanguage=0422 (uk-UA).' -ForegroundColor Green
    Write-Log 'Reiestr Nls\Language: 0422' -Color Green
    if ($installMode -eq 'All') {
        Write-Host '  Kopiiuvannia na ekran vitannia + novi korystuvachi...' -ForegroundColor Yellow
        try {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $True -NewUser $True -ErrorAction Stop
            Write-Host '  [OK] Skopiiovano: ekran vitannia + novi korystuvachi.' -ForegroundColor Green
            Write-Log 'Skopiiovano: WelcomeScreen+NewUser' -Color Green
        } catch {
            Write-Host "  [!] Copy-UserInternationalSettingsToSystem ne vdalosia (mozhlyvo Win10): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Log "Kopiiuvannia: $($_.Exception.Message)" -Color Yellow
        }
        Write-Host ''
        Write-Host '  [!] Spetsialni nalashtuvannia profiliv NE zminiatsia avtomatychno.' -ForegroundColor Red
        Write-Host '      Kozhen korystuvach mae uviity ta vstanovyty movu vruchnu.' -ForegroundColor Yellow
        Write-Log 'Spetsialni nalashtuvannia profiliv ne zmineni' -Color Red
    }
} catch {
    Write-Host '  [!] Ne vdalosia vstanovyty movu interfeisu (ne krytychno):' -ForegroundColor Yellow
    Write-Host "     $($_.Exception.Message)" -ForegroundColor Gray
    Write-Log "Mova interfeisu: $($_.Exception.Message)" -Color Yellow
}
Show-ProgressBar -Percent 85 -Label 'Mova interfeisu'
#endregion

#region === 9. Layouts ===
Show-FlagHeader
Write-Step '*** Krok 9/10 ***' 'Ochyshchennia mov ta nalashtuvannia rozkladok'
Write-Host '  Potochni movy v systemi:' -ForegroundColor Gray
Get-WinUserLanguageList | ForEach-Object { Write-Host "    - $($_.LanguageTag)" -ForegroundColor Gray }

Write-Host '  Vstanovlennia chystoho spysku: uk-UA (osnovna) + en-US...' -ForegroundColor Yellow
try {
    $ll = New-WinUserLanguageList -Language 'uk-UA', 'en-US'
    
    # Nalashtuvannia rozkladok dlia uk-UA (Ukrainska)
    $uk = $ll | Where-Object { $_.LanguageTag -eq 'uk-UA' }
    $uk.InputMethodTips.Clear()
    $uk.InputMethodTips.Add('0422:00000422')
    
    # Nalashtuvannia rozkladok dlia en-US (Anheliiska USA)
    $en = $ll | Where-Object { $_.LanguageTag -eq 'en-US' }
    $en.InputMethodTips.Clear()
    $en.InputMethodTips.Add('0409:00000409')
    
    Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction Stop
    Write-Host '  [OK] Movy ta rozkladky vstanovleno (UKR + ENG).' -ForegroundColor Green
    Write-Log 'Movy vstanovleno: uk-UA, en-US' -Color Green
    
    Write-Host '  Nalashtuvannia peremykannia Shift+Alt...' -ForegroundColor Yellow
    $togglePath = 'HKCU:\Keyboard Layout\Toggle'
    if (-not (Test-Path $togglePath)) { New-Item -Path $togglePath -Force | Out-Null }
    Set-ItemProperty -Path $togglePath -Name 'Hotkey' -Value 1 -ErrorAction Stop
    Write-Host '  [OK] Peremykannia vstanovleno na Shift+Alt.' -ForegroundColor Green
    Write-Log 'Hotkey vstanovleno na Shift+Alt' -Color Green
} catch {
    Write-Host '  [!] Pomylka nalashtuvannia rozkladok (ne krytychno):' -ForegroundColor Yellow
    Write-Host "     $($_.Exception.Message)" -ForegroundColor Gray
    Write-Log "Pomylka Layouts: $($_.Exception.Message)" -Color Yellow
}
Show-ProgressBar -Percent 90 -Label 'Rozkladky hoto-vi'
#endregion

#region === 10. Optimizations ===
Show-FlagHeader
Write-Step '*** Krok 10/10 ***' 'Optymizatsia klaviatury ta systemy'
Write-Host '  Zastosuvannia systemnykh pokrashchen...' -ForegroundColor Yellow
try {
    # 1. Num Lock pry starti
    Set-ItemProperty -Path 'HKU:\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '80000002' -ErrorAction SilentlyContinue
    
    # 2. Vymknennia Sticky Keys
    Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506' -ErrorAction SilentlyContinue
    
    # 3. Pryskorennia povtoru klavish
    $kbRespPath = 'HKCU:\Control Panel\Accessibility\Keyboard Response'
    if (-not (Test-Path $kbRespPath)) { New-Item -Path $kbRespPath -Force | Out-Null }
    Set-ItemProperty -Path $kbRespPath -Name 'AutoRepeatDelay' -Value '200' -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $kbRespPath -Name 'AutoRepeatRate' -Value '15' -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $kbRespPath -Name 'Flags' -Value '27' -ErrorAction SilentlyContinue
    
    # 4. Systemna lokal
    Set-WinSystemLocale -SystemLocale 'uk-UA' -ErrorAction SilentlyContinue
    
    # 5. GeoID Ukrainy (240)
    Set-UserGEOID -GeoId 240 -ErrorAction SilentlyContinue
    
    # 6. Pryskorennia menu
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '20' -ErrorAction SilentlyContinue
    
    # 7. Vymknennia Beep
    Set-ItemProperty -Path 'HKCU:\Control Panel\Sound' -Name 'Beep' -Value 'no' -ErrorAction SilentlyContinue
    
    Write-Host '  [OK] Vsi optymizatsii uspishno zastosovano.' -ForegroundColor Green
    Write-Log 'Systemni optymizatsii vykonano' -Color Green
} catch {
    Write-Host '  [!] Deyaki optymizatsii ne vdalysia (ne krytychno):' -ForegroundColor Yellow
    Write-Host "     $($_.Exception.Message)" -ForegroundColor Gray
    Write-Log "Pomylka Optimizations: $($_.Exception.Message)" -Color Yellow
}
Show-ProgressBar -Percent 100 -Label 'Vse zaversheno!'
#endregion

#region === Completion ===
Show-FlagHeader
Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '   VSE HOTOVO!' -ForegroundColor Yellow
Write-Host '============================================' -ForegroundColor Green
$elapsed = (Get-Date) - $startTime
Write-Host "Chas: $($elapsed.Minutes)khv $($elapsed.Seconds)sek" -ForegroundColor Gray
Write-Host "Log: $logFile" -ForegroundColor Gray
Write-Host ''
Write-Host 'Perezavantazhyty zaraz? (Y/N): ' -NoNewline -ForegroundColor Yellow
$reboot = Read-Host
if ($reboot -in @('Y','y','Yes','YES','ok','OK','yep')) {
    Write-Host '  Perezavantazhennia... Do zustrichi!' -ForegroundColor Green
    Write-Log 'Zapytuietsia perezavantazhennia' -Color Green
    Start-Sleep -Seconds 2
    Restart-Computer
} else {
    Write-Host '  [i] Ne zabudte perezavantazhyty kompiuter piznishe.' -ForegroundColor Yellow
    Write-Host '  Dyakuiemo za vykorystannia Ukrainizator!' -ForegroundColor Cyan
    Write-Log 'Korystuvach vidmovyvsia vid perezavantazhennia' -Color Yellow
    pause
}
#endregion