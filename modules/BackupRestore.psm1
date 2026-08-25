# modules/BackupRestore.psm1
# ============================================================
# Ukrainizator - резервні знімки налаштувань (для -Revert)
# та режим відкату.
# ============================================================

function Save-SettingsSnapshot {
    # Зберігає знімок поточних мовних/регіональних налаштувань у backup/.
    # Ротація: лишаємо тільки 5 останніх знімків.
    try {
        $backupObj = [ordered]@{
            Timestamp     = (Get-Date).ToString('o')
            SystemLocale  = (Get-WinSystemLocale -ErrorAction SilentlyContinue).Name
            UILanguage    = (Get-WinUILanguageOverride -ErrorAction SilentlyContinue).Name
            Culture       = (Get-Culture).Name
            GeoId         = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
            LanguageList  = @((Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }))
        }
        $backupFile = Join-Path $global:BackupDir "Ukrainizator_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $backupObj | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
        Get-ChildItem -Path $global:BackupDir -Filter 'Ukrainizator_backup_*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Log (Get-LocalizedMessage 'snapshot_saved' (Split-Path $backupFile -Leaf)) -Color DarkGreen
        return $true
    } catch {
        Write-Log (Get-LocalizedMessage 'snapshot_failed' (Get-FriendlyErrorMessage $_.Exception.Message)) -Color DarkYellow
        return $false
    }
}

function Move-LegacySnapshots {
    # Якщо лишились старі знімки в корені теки (з версій до 5.0.0) -
    # переносимо в backup/, щоб -Revert однаково їх бачив.
    param([string]$ScriptRoot)
    Get-ChildItem -Path $ScriptRoot -Filter 'Ukrainizator_backup_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
        Move-Item -Path $_.FullName -Destination (Join-Path $global:BackupDir $_.Name) -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RevertMode {
    # Повний цикл відкату: знаходить останній знімок, питає підтвердження,
    # відновлює SystemLocale / UILanguage / Culture / GeoId / LanguageList,
    # виводить підсумковий звіт.
    param([switch]$WhatIf)

    Write-Log (Get-LocalizedMessage 'revert_mode_started') -Color DarkYellow

    $backupPattern = Join-Path $global:BackupDir 'Ukrainizator_backup_*.json'
    $lastBackup = Get-ChildItem -Path $backupPattern -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $lastBackup) {
        Set-InfoPanel -Style 'Error' -Lines @(
            (Get-LocalizedMessage 'revert_no_backup_1'),
            (Get-LocalizedMessage 'revert_no_backup_2')
        )
        Write-Log (Get-LocalizedMessage 'revert_no_backup_log') -Color Red
        Write-Host ''
        Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        Restore-Console
        exit 1
    }
    try {
        $bk = Get-Content -Path $lastBackup.FullName -Raw | ConvertFrom-Json
        Set-InfoPanel -Lines @(
            (Get-LocalizedMessage 'revert_found' $lastBackup.LastWriteTime),
            (Get-LocalizedMessage 'revert_will_restore' $bk.SystemLocale $bk.UILanguage $bk.Culture)
        )
        $go = 'Y'
        if (-not $WhatIf) {
            # Dry-run: підтвердження не питаємо, щоб відкат-переглин проходив без зупинок.
            $go = Show-Prompt -Text (Get-LocalizedMessage 'restore_confirm_prompt') -Default 'Y'
        }
        if ($go -notin @('Y','y','Yes','YES')) {
            Write-Log (Get-LocalizedMessage 'revert_cancelled') -Color DarkYellow
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

            # Підсумковий звіт
            Clear-InfoPanel
            Write-Host ''
            Write-Host ('  {0}' -f (Get-LocalizedMessage 'revert_report_title')) -ForegroundColor Cyan
            Write-Host ("  {0}: {1}" -f (Get-LocalizedMessage 'revert_report_locale'), ($bk.SystemLocale -as [string])) -ForegroundColor Gray
            Write-Host ("  {0}: {1}" -f (Get-LocalizedMessage 'revert_report_culture'), ($bk.Culture -as [string])) -ForegroundColor Gray
            Write-Host ("  {0}: {1}" -f (Get-LocalizedMessage 'revert_report_geo'), ($bk.GeoId -as [string])) -ForegroundColor Gray
            $langListStr = if ($bk.LanguageList) { ($bk.LanguageList -join ', ') } else { '-' }
            Write-Host ("  {0}: {1}" -f (Get-LocalizedMessage 'revert_report_langs'), $langListStr) -ForegroundColor Gray
            Write-Host ''
            Write-Host ('  {0}' -f (Get-LocalizedMessage 'revert_report_success')) -ForegroundColor Green
            Write-Log (Get-LocalizedMessage 'settings_restored') -Color DarkGreen
        } else {
            Write-Log (Get-LocalizedMessage 'revert_whatif') -Color DarkYellow
        }
        Restore-Console
        Write-Host ''
        Write-Host "  $(Get-LocalizedMessage 'dont_forget_reboot')" -ForegroundColor DarkYellow
        Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        exit 0
    } catch {
        Write-Host ''
        Write-Host "  $(Get-LocalizedMessage 'revert_read_failed' $_.Exception.Message)" -ForegroundColor Red
        Write-Host "  $(Get-LocalizedMessage 'press_any_key_to_exit')" -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
        Restore-Console
        exit 1
    }
}
