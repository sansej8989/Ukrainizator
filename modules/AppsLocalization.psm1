# modules/AppsLocalization.psm1
# ============================================================
# Ukrainizator - локалізація стороннього ПЗ:
# VS Code (settings.json -> locale: uk) та Git (commitEncoding utf-8).
# ============================================================

function Set-AppsUkrainianLocale {
    param()

    $results = [System.Collections.ArrayList]::new()

    # === VS Code ===
    $vscodeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (Test-Path $vscodeSettings) {
        try {
            $raw = Get-Content -Path $vscodeSettings -Raw -Encoding UTF8 -ErrorAction Stop
            $settings = $raw | ConvertFrom-Json -ErrorAction Stop
            $changed = $false
            if (-not $settings.PSObject.Properties['locale'] -or $settings.locale -ne 'uk') {
                $settings | Add-Member -NotePropertyName 'locale' -NotePropertyValue 'uk' -Force
                $changed = $true
            }
            if ($changed) {
                $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $vscodeSettings -Encoding UTF8 -ErrorAction Stop
                [void]$results.Add([pscustomobject]@{
                    App = 'VS Code'
                    Status = 'OK'
                    Message = (Get-LocalizedMessage 'apps_vscode_updated')
                })
            } else {
                [void]$results.Add([pscustomobject]@{
                    App = 'VS Code'
                    Status = 'OK'
                    Message = (Get-LocalizedMessage 'apps_vscode_already_uk')
                })
            }
        } catch {
            [void]$results.Add([pscustomobject]@{
                App = 'VS Code'
                Status = 'ERROR'
                Message = (Get-LocalizedMessage 'apps_vscode_failed' $_.Exception.Message)
            })
        }
    } else {
        [void]$results.Add([pscustomobject]@{
            App = 'VS Code'
            Status = 'SKIP'
            Message = (Get-LocalizedMessage 'apps_vscode_missing')
        })
    }

    # === Git ===
    try {
        $gitPath = Get-Command git -ErrorAction SilentlyContinue
        if ($gitPath) {
            git config --global i18n.commitEncoding utf-8 | Out-Null
            [void]$results.Add([pscustomobject]@{
                App = 'Git'
                Status = 'OK'
                Message = (Get-LocalizedMessage 'apps_git_configured')
            })
        } else {
            [void]$results.Add([pscustomobject]@{
                App = 'Git'
                Status = 'SKIP'
                Message = (Get-LocalizedMessage 'apps_git_failed' 'git not found in PATH')
            })
        }
    } catch {
        [void]$results.Add([pscustomobject]@{
            App = 'Git'
            Status = 'ERROR'
            Message = (Get-LocalizedMessage 'apps_git_failed' $_.Exception.Message)
        })
    }

    # === Вивід результатів ===
    Write-Host ''
    foreach ($r in $results) {
        $color = switch ($r.Status) {
            'OK'     { 'Green' }
            'ERROR'  { 'Red' }
            'SKIP'   { 'Yellow' }
            default  { 'Gray' }
        }
        Write-Host ("  [{0}] {1}: {2}" -f $r.Status, $r.App, $r.Message) -ForegroundColor $color
    }
    Write-Host ''

    return $results
}
