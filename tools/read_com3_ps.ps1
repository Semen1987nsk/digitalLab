# Read Arduino Mega 2560 on COM3 - PowerShell .NET approach
# Try multiple approaches to handle driver quirks

Write-Host "=== Arduino Mega 2560 on COM3 ===" -ForegroundColor Cyan
Write-Host ""

# First check port details
$portInfo = Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'COM3' }
Write-Host "Device: $($portInfo.Name)"
Write-Host "Status: $($portInfo.Status)"
Write-Host "Driver: $($portInfo.Service)"
Write-Host ""

# Approach 1: Simple .NET SerialPort with minimal config
foreach ($baud in @(9600, 115200, 57600, 38400)) {
    Write-Host "--- Trying $baud baud ---" -ForegroundColor Yellow
    
    try {
        $port = New-Object System.IO.Ports.SerialPort
        $port.PortName = "COM3"
        $port.BaudRate = $baud
        $port.DataBits = 8
        $port.Parity = [System.IO.Ports.Parity]::None
        $port.StopBits = [System.IO.Ports.StopBits]::One
        $port.Handshake = [System.IO.Ports.Handshake]::None
        $port.ReadTimeout = 3000
        $port.WriteTimeout = 1000
        $port.DtrEnable = $true
        $port.RtsEnable = $false
        $port.Encoding = [System.Text.Encoding]::ASCII
        
        $port.Open()
        Write-Host "  Port opened!" -ForegroundColor Green
        
        # Wait for Arduino reset (DTR toggle causes reset)
        Start-Sleep -Milliseconds 2500
        
        # Discard any buffer garbage
        $port.DiscardInBuffer()
        
        # Read lines
        $gotData = $false
        for ($i = 0; $i -lt 10; $i++) {
            try {
                $line = $port.ReadLine()
                Write-Host "  [$i] $line" -ForegroundColor White
                $gotData = $true
            } catch [System.TimeoutException] {
                Write-Host "  [$i] timeout" -ForegroundColor DarkGray
                # Try reading available bytes instead
                if ($port.BytesToRead -gt 0) {
                    $bytes = New-Object byte[] $port.BytesToRead
                    $port.Read($bytes, 0, $bytes.Length)
                    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
                    Write-Host "  [$i] RAW: $text" -ForegroundColor Magenta
                    $gotData = $true
                }
                break
            } catch {
                Write-Host "  [$i] Error: $($_.Exception.Message)" -ForegroundColor Red
                break
            }
        }
        
        $port.Close()
        $port.Dispose()
        
        if ($gotData) {
            Write-Host "`n  SUCCESS at $baud baud!" -ForegroundColor Green
            break
        }
    } catch {
        $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-Host "  Failed: $msg" -ForegroundColor Red
        if ($port -and $port.IsOpen) { $port.Close() }
        if ($port) { $port.Dispose() }
    }
    
    Start-Sleep -Milliseconds 500
}

Write-Host "`nDone." -ForegroundColor Cyan
