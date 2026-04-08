# Ukrainian Language Installation Script
# Verification: SHA256 hash of this file will be provided separately.

Write-Host "Встановлення мовного пакета uk-UA..."
Install-Language -Language "uk-UA" -CopyToSettings -ExcludeFeatures

Write-Host "Застосування системної мови uk-UA..."
Set-SystemPreferredUILanguage -Language "uk-UA"

Write-Host "Поточні мовні параметри:"
Get-WinUserLanguageList | Format-Table

Write-Host "Готово. Перезавантаження НЕ виконується автоматично."
Write-Host "Для застосування змін рекомендується вручну перезавантажити систему."
