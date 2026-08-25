# modules/Localization.psm1
# ============================================================
# Ukrainizator - локалізація: завантаження JSON-словників,
# отримання повідомлень за ключем, дружні переклади типових
# .NET/PowerShell винятків.
# ============================================================

$global:CurrentLanguage = 'uk-UA'   # За замовчуванням
$global:LocalizedStrings = @{}
$global:LocalePath = $null

function Write-DebugLog {
    # Базова діагностика. Активується $global:DebugMode = $true.
    param(
        [string]$Message,
        [string]$Color = 'DarkGray'
    )
    if ($global:DebugMode) {
        Write-Host "DEBUG: $Message" -ForegroundColor $Color
    }
}

function Initialize-Localization {
    param([string]$LocalePath)
    $global:LocalePath = $LocalePath
}

function Read-LocalizationFile {
    param([string]$langCode)
    $filePath = Join-Path $global:LocalePath "$langCode.json"
    Write-DebugLog "Attempting to load localization file: $filePath"
    if (Test-Path $filePath) {
        try {
            $rawContent = Get-Content -Raw -Path $filePath -Encoding UTF8
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
    }
    Write-DebugLog "Localization file not found: $filePath"
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
                # [string]::Format надійніше за оператор -f для масиву аргументів:
                # не "розгортає" вкладені колекції і не ламається, якщо аргумент
                # один або їх кілька.
                return [string]::Format($message, $MessageArgs)
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
    # найпоширеніші причини, а невідомі лишаємо як є (з оригіналом у дужках).
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
