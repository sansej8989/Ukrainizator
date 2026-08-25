# modules/Preflight.psm1
# ============================================================
# Ukrainizator - попередній аудит системи перед виконанням змін.
# Перевіряє інтернет, вільне місце на диску та службу відновлення.
# ============================================================

function Test-SystemReadiness {
    param()

    $results = [System.Collections.ArrayList]::new()

    # === Інтернет ===
    $internetOk = $false
    try {
        try {
            Invoke-WebRequest -Uri 'https://github.com' -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop | Out-Null
            $internetOk = $true
        } catch {
            try {
                Test-Connection -ComputerName github.com -Count 2 -Quiet -ErrorAction Stop | Out-Null
                $internetOk = $true
            } catch {}
        }
    } catch {}

    $status = if ($internetOk) { (Get-LocalizedMessage 'preflight_ok') } else { (Get-LocalizedMessage 'preflight_critical') }
    $color = if ($internetOk) { 'Green' } else { 'Red' }
    [void]$results.Add([pscustomobject]@{
        Name = (Get-LocalizedMessage 'preflight_internet')
        Status = $status
        Color = $color
    })

    # === Дисковий простір ===
    $freeGB = 0
    try {
        $driveName = $env:SystemDrive.TrimEnd('\')
        $disk = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
        if ($disk) {
            $freeGB = [math]::Round($disk.Free / 1GB, 1)
        }
    } catch {}

    $diskOk = $freeGB -ge 0.5
    $status = if ($diskOk) { (Get-LocalizedMessage 'preflight_ok') } else { (Get-LocalizedMessage 'preflight_critical') }
    $color = if ($diskOk) { 'Green' } else { 'Red' }
    [void]$results.Add([pscustomobject]@{
        Name = (Get-LocalizedMessage 'preflight_disk' $env:SystemDrive $freeGB)
        Status = $status
        Color = $color
    })

    # === Служба відновлення ===
    $srStatus = (Get-LocalizedMessage 'preflight_critical')
    $srColor = 'Red'
    try {
        $srService = Get-Service -Name srservice -ErrorAction SilentlyContinue
        if ($srService -and $srService.Status -eq 'Running') {
            $srStatus = (Get-LocalizedMessage 'preflight_ok')
            $srColor = 'Green'
        } elseif ($srService) {
            $srStatus = $srService.Status
            $srColor = 'Yellow'
        }
    } catch {}

    [void]$results.Add([pscustomobject]@{
        Name = (Get-LocalizedMessage 'preflight_srservice' $srStatus)
        Status = if ($srColor -eq 'Green') { (Get-LocalizedMessage 'preflight_ok') } elseif ($srColor -eq 'Yellow') { (Get-LocalizedMessage 'preflight_warning') } else { (Get-LocalizedMessage 'preflight_critical') }
        Color = $srColor
    })

    # === Вивід результатів ===
    Write-Host ''
    Write-Host ('  {0}' -f (Get-LocalizedMessage 'preflight_title')) -ForegroundColor Cyan
    foreach ($r in $results) {
        Write-Host ("  [{0}] {1}" -f $r.Status, $r.Name) -ForegroundColor $r.Color
    }
    Write-Host ''

    # === Перевірка критичних зауважень ===
    $hasCritical = $results | Where-Object { $_.Status -eq (Get-LocalizedMessage 'preflight_critical') }
    if ($hasCritical) {
        $answer = Read-Host (Get-LocalizedMessage 'preflight_continue_prompt')
        if ($answer -notin @('Y','y','Yes','YES')) {
            Write-Host (Get-LocalizedMessage 'preflight_abort') -ForegroundColor Yellow
            exit 1
        }
    }

    return $results
}
