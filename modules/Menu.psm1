# modules/Menu.psm1
# ============================================================
# Ukrainizator - інтерактивне CLI-меню для вибору режиму роботи.
# Показується лише при запуску без параметрів.
# ============================================================

function Show-InteractiveMenu {
    param()

    $menuItems = @(
        [pscustomobject]@{ Key = '1'; Profile = 'Full';            Label = (Get-LocalizedMessage 'menu_full') }
        [pscustomobject]@{ Key = '2'; Profile = 'Language';         Label = (Get-LocalizedMessage 'menu_language') }
        [pscustomobject]@{ Key = '3'; Profile = 'Layouts';          Label = (Get-LocalizedMessage 'menu_layouts') }
        [pscustomobject]@{ Key = '4'; Profile = 'Derussification';  Label = (Get-LocalizedMessage 'menu_derussification') }
        [pscustomobject]@{ Key = '5'; Profile = 'Apps';             Label = (Get-LocalizedMessage 'menu_apps') }
        [pscustomobject]@{ Key = '6'; Profile = 'Revert';           Label = (Get-LocalizedMessage 'menu_revert') }
        [pscustomobject]@{ Key = '0'; Profile = 'Exit';             Label = (Get-LocalizedMessage 'menu_exit') }
    )

    while ($true) {
        try { Clear-Host } catch {}

        Write-Host ''
        Write-Host '  ==================================================' -ForegroundColor Cyan
        Write-Host ('  {0}' -f (Get-LocalizedMessage 'menu_title')) -ForegroundColor White
        Write-Host '  ==================================================' -ForegroundColor Cyan
        foreach ($item in $menuItems) {
            Write-Host ("  [{0}] {1}" -f $item.Key, $item.Label) -ForegroundColor Gray
        }
        Write-Host '  ==================================================' -ForegroundColor Cyan
        Write-Host ''

        $choice = Read-Host (Get-LocalizedMessage 'menu_prompt')

        $valid = $menuItems | Where-Object { $_.Key -eq $choice }
        if ($valid) {
            return $valid.Profile
        }

        Write-Host (Get-LocalizedMessage 'menu_invalid') -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}
