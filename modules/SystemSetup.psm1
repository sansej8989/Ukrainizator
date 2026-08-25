# modules/SystemSetup.psm1
# ============================================================
# Ukrainizator - системні операції: визначення збірки Windows,
# встановлення мовного пакета (сучасний API або DISM),
# дерусифікація, оптимізації, верифікація результату.
# ============================================================

function Test-AlreadyUkrainized {
    # Швидка перевірка "вже налаштовано" (ідемпотентність).
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

function Get-WindowsVersionInfo {
    # Визначення збірки/редакції Windows. ProductName у реєстрі нерідко й досі
    # каже "Windows 10 ..." навіть на Windows 11 (build 22000+) - виправляємо
    # назву за номером збірки, а не за тим, що написано в реєстрі.
    $osInfo = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = [int]$osInfo.CurrentBuildNumber
    $display = if ($osInfo.DisplayVersion) { $osInfo.DisplayVersion } else { $osInfo.ReleaseId }
    $name = $osInfo.ProductName
    if ($build -ge 22000 -and $name -match 'Windows 10') {
        $name = $name -replace 'Windows 10', 'Windows 11'
    }
    return [pscustomobject]@{ Build = $build; DisplayVersion = $display; ProductName = $name }
}

function Test-UkrainianLanguageInstalled {
    param([string]$LanguageTag = 'uk-UA')
    if (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue) {
        if ((Get-InstalledLanguage | Out-String) -match $LanguageTag) { return $true }
    }
    if ((Get-WinUserLanguageList | Out-String) -match $LanguageTag) { return $true }
    if (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue) {
        $cap = Get-WindowsCapability -Online -Name "Language.Basic~~~$LanguageTag~0.0.1.0" -ErrorAction SilentlyContinue
        if ($cap -and $cap.State -eq 'Installed') { return $true }
    }
    return $false
}

function Install-UkrainianLanguagePack {
    # Встановлює мовний пакет: сучасний Install-Language (Win11/newer Win10)
    # або універсальний DISM-шлях (базовий пакет + best-effort додаткові).
    param(
        [string]$LanguageTag = 'uk-UA',
        [bool]$UseModernApi
    )
    if ($UseModernApi) {
        Install-Language -Language $LanguageTag -CopyToSettings -ExcludeFeatures -ErrorAction Stop -WarningAction SilentlyContinue
        return
    }
    Add-WindowsCapability -Online -Name "Language.Basic~~~$LanguageTag~0.0.1.0" -ErrorAction Stop -WarningAction SilentlyContinue
    foreach ($extra in @('Language.Fonts.Cyrl', 'Language.Handwriting', 'Language.OCR', 'Language.Speech', 'Language.TextToSpeech')) {
        try {
            $capName = "$extra~~~$LanguageTag~0.0.1.0"
            $capInfo = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
            if ($capInfo -and $capInfo.State -ne 'Installed') {
                Add-WindowsCapability -Online -Name $capName -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            }
        } catch {
            Write-DebugLog (Get-LocalizedMessage 'extra_component_skipped_debug' $extra)
        }
    }
    $ll = Get-WinUserLanguageList
    if (-not ($ll | Where-Object { $_.LanguageTag -eq $LanguageTag })) {
        $ll.Add($LanguageTag)
        Set-WinUserLanguageList -LanguageList $ll -Force -ErrorAction SilentlyContinue
    }
}

function Remove-RussianComponents {
    # Глибша дерусифікація: додаткові ru-* компоненти Windows (розпізнавання
    # мовлення, рукописне введення, синтез мовлення, OCR) - вони НЕ прибираються
    # самим лише видаленням мови зі списку розкладок.
    try {
        $ruCapabilities = Get-WindowsCapability -Online -ErrorAction Stop |
            Where-Object { $_.Name -match '^Language\.(Speech|Handwriting|TextToSpeech|OCR)~.*~ru-RU~' -and $_.State -eq 'Installed' }
        foreach ($cap in $ruCapabilities) {
            try {
                Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                Write-Log (Get-LocalizedMessage 'removed_component' $cap.Name) -Color DarkYellow
            } catch {
                Write-Log (Get-LocalizedMessage 'component_remove_failed' $cap.Name (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
            }
        }
        if ($ruCapabilities.Count -eq 0) { Write-Log (Get-LocalizedMessage 'no_ru_components') -Color DarkGreen }
    } catch {
        Write-Log (Get-LocalizedMessage 'component_scan_error' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
    }
}

function Clear-TypingSuggestionsCache {
    # Кеш підказок під час набору тексту (може містити напрацьовані ru-слова).
    # Офіційно документований шлях Microsoft для скидання персоналізації вводу.
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
        Write-Log (Get-LocalizedMessage 'typing_cache_cleaned') -Color DarkGreen
    } catch {
        Write-Log (Get-LocalizedMessage 'typing_cache_error' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
    }
}

function Invoke-Optimizations {
    # Оптимізації реєстру + очищення кешу шрифтів + перезапуск провідника.
    # Повертає $true, якщо всі реєстрові твіки застосовано успішно.
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

    return $optSuccess
}

function Get-VerificationChecks {
    # Верифікація результату: повертає список перевірок @{ Name; Ok; Detail }.
    # Get-WinUserLanguageList кешує результат на весь час життя процесу -
    # тому мови читаємо напряму з реєстру, без кешування.
    $checks = New-Object System.Collections.ArrayList
    $sysLocale = (Get-WinSystemLocale -ErrorAction SilentlyContinue).Name
    [void]$checks.Add(@{ Name = (Get-LocalizedMessage 'check_sys_locale');      Ok = ($sysLocale -eq 'uk-UA'); Detail = $sysLocale })
    $uiLang = (Get-WinUILanguageOverride -ErrorAction SilentlyContinue).Name
    # Windows іноді повертає скорочений тег "uk" замість "uk-UA" - це та сама
    # мова, просто інший формат запису, тому приймаємо обидва варіанти.
    [void]$checks.Add(@{ Name = (Get-LocalizedMessage 'check_ui_language');     Ok = ($uiLang -eq 'uk-UA' -or $uiLang -eq 'uk'); Detail = $uiLang })
    $culture = (Get-Culture).Name
    [void]$checks.Add(@{ Name = (Get-LocalizedMessage 'check_regional_format'); Ok = ($culture -eq 'uk-UA');   Detail = $culture })

    $hasUk = $false; $hasRu = $false
    try {
        $userProfileLangs = (Get-ItemProperty -Path 'HKCU:\Control Panel\International\User Profile' -Name 'Languages' -ErrorAction Stop).Languages
        $hasUk = [bool]($userProfileLangs -contains 'uk-UA')
        $hasRu = [bool]($userProfileLangs | Where-Object { $_ -match 'ru' })
    } catch {
        # Резервний варіант, якщо ключа реєстру ще немає - старий спосіб через cmdlet
        $llCheck = Get-WinUserLanguageList
        $hasUk = [bool]($llCheck | Where-Object { $_.LanguageTag -eq 'uk-UA' })
        $hasRu = [bool]($llCheck | Where-Object { $_.LanguageTag -match 'ru' })
    }
    $yesText = Get-LocalizedMessage 'verify_yes'
    $noText  = Get-LocalizedMessage 'verify_no'
    [void]$checks.Add(@{ Name = (Get-LocalizedMessage 'check_layout_present'); Ok = $hasUk;        Detail = if ($hasUk) { $yesText } else { $noText } })
    [void]$checks.Add(@{ Name = (Get-LocalizedMessage 'check_ru_removed');     Ok = (-not $hasRu); Detail = if ($hasRu) { Get-LocalizedMessage 'verify_still_there' } else { Get-LocalizedMessage 'verify_removed' } })
    $geoId = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
    [void]$checks.Add(@{ Name = (Get-LocalizedMessage 'check_region_geo');     Ok = ($geoId -eq 240); Detail = "GeoId=$geoId" })

    return ,$checks
}



