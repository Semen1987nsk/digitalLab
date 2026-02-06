# Force-Fix USB Script for Digital Lab (AGGRESSIVE VERSION)
# Run as Administrator!

$ErrorActionPreference = "SilentlyContinue"

function Write-Log {
    param($msg, $color="White")
    Write-Host "[FIX-USB] $msg" -ForegroundColor $color
}

# 1. Check Admin
$isAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).Groups -match 'S-1-5-32-544')
if (-not $isAdmin) {
    Write-Log "OSHIBKA: Nuzhny prava Administratora!" "Red"
    Write-Log "Zapustite etot skript ot imeni Administratora." "Yellow"
    Read-Host "Nazhmite Enter..."
    exit
}

Write-Log "=== AGGRESSIVE USB FIX ===" "Cyan"

# 2. Disable USB Power Management (common cause of Arduino detection issues)
Write-Log "Disabling USB Power Management..." "Yellow"
$usbDevices = Get-WmiObject Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like "USB\*" }
foreach ($device in $usbDevices) {
    $deviceId = $device.PNPDeviceID
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceId\Device Parameters"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
}

# 3. Kill ALL VID_0000 devices (stuck descriptors)
Write-Log "Removing ALL stuck VID_0000 devices..." "Yellow"
$badDevices = Get-PnpDevice | Where-Object { $_.InstanceId -like "*VID_0000*" }
$count = 0
foreach ($dev in $badDevices) {
    Write-Log "  Removing: $($dev.InstanceId)" "DarkGray"
    $result = pnputil /remove-device $dev.InstanceId 2>&1
    $count++
}
Write-Log "Removed $count stuck devices." "Green"

# 4. Clear USB Device Cache in Registry
Write-Log "Clearing USB device cache..." "Yellow"
$cachePaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{a5dcbf10-6530-11d2-901f-00c04fb951ed}",
    "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{53f56307-b6bf-11d0-94f2-00a0c91efb8b}"
)
foreach ($path in $cachePaths) {
    if (Test-Path $path) {
        Get-ChildItem $path | Where-Object { $_.Name -match "VID_0000" } | ForEach-Object {
            Write-Log "  Deleting cache: $($_.Name)" "DarkGray"
            Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 5. Reset USB Host Controllers (not just hubs)
Write-Log "Restarting USB Host Controllers..." "Yellow"
$controllers = Get-PnpDevice -Class "USB" | Where-Object { 
    $_.FriendlyName -match "Host Controller|xHCI|EHCI|UHCI" -and $_.Status -eq "OK" 
}
foreach ($ctrl in $controllers) {
    Write-Log "  Restarting: $($ctrl.FriendlyName)" "DarkGray"
    Disable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1000
    Enable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
}

# 6. Force PnP Rescan
Write-Log "Triggering full device rescan..." "Yellow"
pnputil /scan-devices

Write-Log "" "White"
Write-Log "=== GOTOVO ===" "Green"
Write-Log "Teper:" "Cyan"
Write-Log "  1. Otklyuchite Arduino ot USB" "White"
Write-Log "  2. Podozhdite 5 sekund" "White"
Write-Log "  3. Podklyuchite v DRUGOY port (luchshe USB 2.0 - chernyy)" "White"
Write-Log "" "White"

Read-Host "Nazhmite Enter chtoby zakryt..."
