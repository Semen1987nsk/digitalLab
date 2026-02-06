# Try different baud rates and send commands
$port = "COM6"
$baudRates = @(9600, 115200, 57600, 38400, 19200)

foreach ($baud in $baudRates) {
    Write-Host "`n=== Trying $baud baud ===" -ForegroundColor Cyan
    
    try {
        $serial = New-Object System.IO.Ports.SerialPort $port, $baud, None, 8, One
        $serial.ReadTimeout = 500
        $serial.WriteTimeout = 500
        $serial.Open()
        
        # Try sending common commands
        $commands = @("", "AT", "?", "M", "R", "S")
        
        foreach ($cmd in $commands) {
            if ($cmd -ne "") {
                $serial.WriteLine($cmd)
                Write-Host "Sent: '$cmd'" -ForegroundColor Yellow
            }
            
            Start-Sleep -Milliseconds 500
            
            # Try to read
            try {
                $available = $serial.BytesToRead
                if ($available -gt 0) {
                    $data = $serial.ReadExisting()
                    Write-Host "Received ($available bytes): $data" -ForegroundColor Green
                }
            } catch {}
        }
        
        $serial.Close()
        
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

Write-Host "`nDone!" -ForegroundColor Cyan
