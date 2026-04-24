param(
    [switch]$Repair,
    [switch]$IncludeFTDI,
    [switch]$RemoveGhosts
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$TargetVids = @('2341', '1A86', '10C4')
if ($IncludeFTDI) {
    $TargetVids += '0403'
}

function Write-Section {
    param([string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Gray
}

function Write-Ok {
    param([string]$Text)
    Write-Host "[OK]   $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Test-IsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RegistryActiveComPorts {
    $result = [ordered]@{}
    try {
        $raw = & reg query 'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM' 2>$null
        foreach ($line in $raw) {
            if ($line -match 'COM\d+') {
                $port = $Matches[0].ToUpperInvariant()
                $result[$port] = $true
            }
        }
    } catch {
        Write-Warn "Failed to read SERIALCOMM: $($_.Exception.Message)"
    }
    return $result
}

function Get-RegistryPortMappings {
    $records = New-Object System.Collections.Generic.List[object]
    $paths = @(
        'HKLM\SYSTEM\CurrentControlSet\Enum\USB',
        'HKLM\SYSTEM\CurrentControlSet\Enum\FTDIBUS'
    )

    foreach ($path in $paths) {
        try {
            $raw = & reg query $path /s /v PortName 2>$null
        } catch {
            continue
        }

        $currentKey = $null
        foreach ($line in $raw) {
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith('HKEY_')) {
                $currentKey = $trimmed
                continue
            }

            if (-not $currentKey) { continue }
            if ($trimmed -notmatch 'PortName' -or $trimmed -notmatch 'REG_SZ') { continue }
            if ($trimmed -notmatch 'COM\d+') { continue }

            $portName = $Matches[0].ToUpperInvariant()
            $deviceVid = $null
            $devicePid = $null
            if ($currentKey -match 'VID_([0-9A-Fa-f]{4})') {
                $deviceVid = $Matches[1].ToUpperInvariant()
            }
            if ($currentKey -match 'PID_([0-9A-Fa-f]{4})') {
                $devicePid = $Matches[1].ToUpperInvariant()
            }

            $records.Add([pscustomobject]@{
                PortName     = $portName
                InstanceId   = $currentKey.Replace('HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\', '')
                Vid          = $deviceVid
                Pid          = $devicePid
                RegistryRoot = $path
            })
        }
    }

    return $records
}

function Get-PortDevices {
    try {
        return Get-PnpDevice -Class Ports -ErrorAction Stop | ForEach-Object {
            $portName = $null
            if ($_.FriendlyName -match '\((COM\d+)\)') {
                $portName = $Matches[1].ToUpperInvariant()
            }

            [pscustomobject]@{
                FriendlyName = $_.FriendlyName
                Status       = $_.Status
                Class        = $_.Class
                InstanceId   = $_.InstanceId
                PortName     = $portName
            }
        }
    } catch {
        throw "Get-PnpDevice is unavailable: $($_.Exception.Message)"
    }
}

function Test-TargetDevice {
    param(
        [AllowNull()][string]$InstanceId,
        [AllowNull()][string]$Vid,
        [AllowNull()][string]$FriendlyName
    )

    $normalizedInstanceId = if ($InstanceId) { $InstanceId.ToUpperInvariant() } else { '' }
    $normalizedFriendly = if ($FriendlyName) { $FriendlyName.ToUpperInvariant() } else { '' }

    foreach ($targetVid in $TargetVids) {
        if ($Vid -eq $targetVid) { return $true }
        if ($normalizedInstanceId -match "VID_$targetVid") { return $true }
    }

    if ($normalizedFriendly -match 'ARDUINO|CH340|CP210|USB SERIAL PORT|USB SERIAL DEVICE') {
        return $true
    }

    return $false
}

function Get-DiagnosticRows {
    param(
        [Parameter(Mandatory)]$ActivePorts,
        [Parameter(Mandatory)]$Mappings,
        [Parameter(Mandatory)]$PortDevices
    )

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($device in $PortDevices) {
        $mapping = $null
        if ($device.PortName) {
            $mapping = $Mappings | Where-Object { $_.PortName -eq $device.PortName } | Select-Object -First 1
        }
        if (-not $mapping) {
            $mapping = $Mappings | Where-Object { $_.InstanceId -eq $device.InstanceId } | Select-Object -First 1
        }

        $deviceVid = if ($mapping) { $mapping.Vid } else { $null }
        $devicePid = if ($mapping) { $mapping.Pid } else { $null }
        $isActive = $false
        if ($device.PortName -and $ActivePorts.Contains($device.PortName)) {
            $isActive = $true
        }

        $isTarget = Test-TargetDevice -InstanceId $device.InstanceId -Vid $deviceVid -FriendlyName $device.FriendlyName
        if (-not $isTarget) { continue }

        $issues = New-Object System.Collections.Generic.List[string]
        if ($device.Status -ne 'OK') {
            $issues.Add("PnP status=$($device.Status)")
        }
        if ($device.PortName -and -not $isActive) {
            $issues.Add('Port missing in SERIALCOMM')
        }
        if (-not $device.PortName) {
            $issues.Add('No COM port extracted from FriendlyName')
        }

        $rows.Add([pscustomobject]@{
            PortName     = $device.PortName
            FriendlyName = $device.FriendlyName
            Status       = $device.Status
            Active       = $isActive
            Vid          = $deviceVid
            Pid          = $devicePid
            InstanceId   = $device.InstanceId
            NeedsRepair  = ($issues.Count -gt 0)
            Issues       = ($issues -join '; ')
        })
    }

    foreach ($mapping in $Mappings) {
        $alreadyKnown = $rows | Where-Object {
            $_.InstanceId -eq $mapping.InstanceId -or ($_.PortName -and $_.PortName -eq $mapping.PortName)
        } | Select-Object -First 1
        if ($alreadyKnown) { continue }

        $isTarget = Test-TargetDevice -InstanceId $mapping.InstanceId -Vid $mapping.Vid -FriendlyName $null
        if (-not $isTarget) { continue }

        $isActive = $ActivePorts.Contains($mapping.PortName)
        $issueText = if ($isActive) { 'Registry entry without PnP device' } else { 'Ghost registry mapping' }

        $rows.Add([pscustomobject]@{
            PortName     = $mapping.PortName
            FriendlyName = 'registry-only device'
            Status       = 'Missing'
            Active       = $isActive
            Vid          = $mapping.Vid
            Pid          = $mapping.Pid
            InstanceId   = $mapping.InstanceId
            NeedsRepair  = $true
            Issues       = $issueText
        })
    }

    return $rows | Sort-Object @{Expression='Active';Descending=$true}, PortName, FriendlyName
}

function Show-DiagnosticReport {
    param([Parameter(Mandatory)]$Rows)

    $rowList = @($Rows)

    Write-Section 'Arduino USB COM diagnosis'
    if (-not $rowList -or $rowList.Count -eq 0) {
        Write-Warn 'No target Arduino or CDC devices were found.'
        return
    }

    $rowList | Select-Object PortName, FriendlyName, Status, Active, Vid, Pid, Issues |
        Format-Table -Wrap -AutoSize | Out-String | Write-Host

    $broken = @($rowList | Where-Object { $_.NeedsRepair })
    if ($broken.Count -eq 0) {
        Write-Ok 'No problematic Arduino or CDC ports found.'
    } else {
        Write-Warn "Problematic entries found: $($broken.Count)"
    }
}

function Invoke-RepairStep {
    param(
        [Parameter(Mandatory)]$Rows
    )

    if (-not (Test-IsAdmin)) {
        throw 'Repair mode requires an elevated PowerShell window.'
    }

    $targets = @($Rows | Where-Object { $_.NeedsRepair })
    if ($targets.Count -eq 0) {
        Write-Ok 'Nothing to repair.'
        return
    }

    Write-Section 'Repair'
    foreach ($row in $targets) {
        Write-Info "Processing $($row.FriendlyName) [$($row.InstanceId)]"

        if ($row.Status -ne 'OK' -and $row.InstanceId -and $row.FriendlyName -ne 'registry-only device') {
            try {
                Enable-PnpDevice -InstanceId $row.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Ok 'Device enabled via Enable-PnpDevice'
            } catch {
                Write-Warn "Enable-PnpDevice failed: $($_.Exception.Message)"
            }

            try {
                & pnputil /restart-device "$($row.InstanceId)" | Out-Null
                Write-Ok 'Device restart requested via pnputil'
            } catch {
                Write-Warn "restart-device failed: $($_.Exception.Message)"
            }
        }

        if ($RemoveGhosts -and (-not $row.Active) -and $row.InstanceId) {
            try {
                & pnputil /remove-device "$($row.InstanceId)" | Out-Null
                Write-Ok 'Ghost or stale device entry removed'
            } catch {
                Write-Warn "remove-device failed: $($_.Exception.Message)"
            }
        }
    }

    Write-Info 'Triggering PnP rescan...'
    & pnputil /scan-devices | Out-Null
    Start-Sleep -Seconds 2
}

Write-Section 'Digital Lab USB Arduino repair tool'
$modeText = if ($Repair) { 'repair' } else { 'diagnostics' }
Write-Info ("Mode: " + $modeText)
Write-Info ("Target VIDs: " + ($TargetVids -join ', '))
if ($Repair -and -not $RemoveGhosts) {
    Write-Info 'Ghost removal is disabled. Add -RemoveGhosts to delete stale disabled entries.'
}

$activePorts = Get-RegistryActiveComPorts
$mappings = Get-RegistryPortMappings
$portDevices = Get-PortDevices
$rows = Get-DiagnosticRows -ActivePorts $activePorts -Mappings $mappings -PortDevices $portDevices
Show-DiagnosticReport -Rows $rows

if ($Repair) {
    Invoke-RepairStep -Rows $rows
    $activePorts = Get-RegistryActiveComPorts
    $mappings = Get-RegistryPortMappings
    $portDevices = Get-PortDevices
    $rows = Get-DiagnosticRows -ActivePorts $activePorts -Mappings $mappings -PortDevices $portDevices
    Show-DiagnosticReport -Rows $rows
}

Write-Section 'Hints'
Write-Host '1. Active=False with Status!=OK usually means a ghost or disabled COM device.' -ForegroundColor White
Write-Host '2. If Arduino still does not appear after repair, unplug and reconnect the USB cable, then run diagnostics again.' -ForegroundColor White
Write-Host '3. Aggressive cleanup command: powershell -ExecutionPolicy Bypass -File tools/repair_arduino_ports.ps1 -Repair -RemoveGhosts' -ForegroundColor White
