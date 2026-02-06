# Read sensor data from COM port
$port = "COM6"
$baud = 57600

Write-Host "Opening $port at $baud baud..."

try {
    $serial = New-Object System.IO.Ports.SerialPort $port, $baud, None, 8, One
    $serial.ReadTimeout = 2000
    $serial.Open()
    
    Write-Host "Port opened. Reading for 10 seconds..."
    
    $end = (Get-Date).AddSeconds(10)
    $count = 0
    
    while ((Get-Date) -lt $end) {
        try {
            $line = $serial.ReadLine()
            $count++
            Write-Host "[$count] $line"
        }
        catch {
            Write-Host "." -NoNewline
        }
    }
    
    $serial.Close()
    Write-Host "`nRead $count lines"
    
} catch {
    Write-Host "ERROR: $_"
}
