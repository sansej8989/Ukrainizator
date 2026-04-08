# ============================================
# Українизатор v1.1 — Для поточного користувача
# ============================================

function Show-Logo {
    Clear-Host
    Write-Host @"
    
    ██╗   ██╗██╗  ██╗██████╗  █████╗ ██╗███╗   ██╗███████╗██████╗ 
    ██║   ██║██║ ██╔╝██╔══██╗██╔══██╗██║████╗  ██║██╔════╝██╔══██╗
    ██║   ██║█████╔╝ ██████╔╝███████║██║██╔██╗ ██║█████╗  ██████╔╝
    ██║   ██║██╔═██╗ ██╔══██╗██╔══██║██║██║╚██╗██║██╔══╝  ██╔══██╗
    ╚██████╔╝██║  ██╗██║  ██║██║  ██║██║██║ ╚████║███████╗██║  ██║
     ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝
"@ -ForegroundColor Cyan
    Write-Host "Версія 1.1 — Українизатор (лише для поточного користувача)" -ForegroundColor Yellow
    Write-Host ""
}

# ===========================
# Вибір мови
# ===========================
function Select-Language {
    Clear-Host
    Show-Logo
    $langs = @(
        @{Tag="uk-UA"; Name="Українська"; Region=225; TimeZone="FLE Standard Time"},
        @{Tag="en-US"; Name="Англійська"; Region=244; TimeZone="Pacific Standard Time"}
    )
    Write-Host "=== Виберіть мову для встановлення ===" -ForegroundColor Cyan
    for ($i=0; $i -lt $langs.Count; $i++) {
        Write-Host "[$($i+1)] $($langs[$i].Name) ($($langs[$i].Tag))"
    }
    Write-Host ""
    $selection = Read-Host "Введіть номер мови"
    if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $langs.Count) {
        Write-Host "Невірний вибір." -ForegroundColor Red
        pause
        exit
    }
    return $langs[[int]$selection - 1]
}

# ===========================
# Функція прогрес-бару
# ===========================
function Show-Progress($percent) {
    $barLength = 40
    $filled = [math]::Round($percent / 100 * $barLength)
    $empty = $barLength - $filled
    $bar = ("█" * $filled) + ("─" * $empty)
    Write-Host "[${bar}] $percent%" -NoNewline
    Write-Host "`r"
}

# ===========================
# Основна функція для поточного користувача
# ===========================
function Set-WindowsSettings {
    param([Parameter(Mandatory=$true)]$Lang)

    Clear-Host
    Show-Logo

    # --- Встановлення мовного пакета ---
    Write-Host "`nВстановлення мовного пакета: $($Lang.Name) ($($Lang.Tag))"
    try {
        Install-Language -Language $Lang.Tag -CopyToSettings -ExcludeFeatures -ErrorAction Stop
        Write-Host "✅ Мовний пакет встановлено."
    } catch {
        Write-Host "❌ Помилка встановлення мовного пакета: $_" -ForegroundColor Red
    }

    # --- Клавіатури ---
    Write-Host "`nНалаштування клавіатур..."
    try {
        $userLangList = New-WinUserLanguageList $Lang.Tag
        $userLangList[0].InputMethodTips.Clear()
        $userLangList[0].InputMethodTips.Add("0422:00000422") # Українська
        $userLangList[0].InputMethodTips.Add("0409:00000409") # Англійська
        Set-WinUserLanguageList -LanguageList $userLangList -Force
        Write-Host "✅ Клавіатурні розкладки застосовано: Українська → Англійська"
    } catch {
        Write-Host "❌ Помилка при налаштуванні клавіатур: $_" -ForegroundColor Red
    }

    # --- Налаштування системи ---
    $steps = @(
        @{ Name="Культура (Culture)"; Action={ Set-Culture $Lang.Tag } },
        @{ Name="Домашнє розташування (Home Location)"; Action={ Set-WinHomeLocation -GeoId $Lang.Region } },
        @{ Name="Системна локаль (System Locale)"; Action={ Set-WinSystemLocale $Lang.Tag } },
        @{ Name="Мова UI (UILanguageOverride)"; Action={ Set-WinUILanguageOverride -Language $Lang.Tag } },
        @{ Name="Часовий пояс (TimeZone)"; Action={ Set-TimeZone -Id $Lang.TimeZone } }
    )

    for ($i=0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]
        Write-Host "`nЗастосовується: $($step.Name)..."
        try {
            & $step.Action
            Write-Host "✅ $($step.Name) застосовано." -ForegroundColor Green
        } catch {
            Write-Host "❌ Помилка при застосуванні $($step.Name): $_" -ForegroundColor Red
        }
        Show-Progress([math]::Round(($i+1)/$steps.Count*100))
        Start-Sleep -Milliseconds 300
    }
}

# ===========================
# Головне меню
# ===========================
Show-Logo
$Lang = Select-Language
Set-WindowsSettings -Lang $Lang

Write-Host "`nБільшість інтерфейсу тепер відображається з новими налаштуваннями."
Write-Host "Рекомендується перезапустити систему для повного застосування змін."
Read-Host "Press Enter to exit..."
