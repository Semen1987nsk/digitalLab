# Скрипт для чтения данных с COM-порта датчика
# Использование: .\read_sensor.ps1 -Port COM6 -BaudRate 57600

param(
    [string]$Port = "COM6",
    [int]$BaudRate = 57600,
    [int]$Seconds = 10
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Чтение данных с датчика расстояния" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Порт: $Port" -ForegroundColor Yellow
Write-Host "Скорость: $BaudRate бод" -ForegroundColor Yellow
Write-Host "Время чтения: $Seconds сек" -ForegroundColor Yellow
Write-Host ""

try {
    $serial = New-Object System.IO.Ports.SerialPort $Port, $BaudRate, None, 8, One
    $serial.ReadTimeout = 1000
    $serial.Open()
    
    Write-Host "Порт открыт. Читаю данные..." -ForegroundColor Green
    Write-Host ""
    
    $endTime = (Get-Date).AddSeconds($Seconds)
    $lineCount = 0
    
    while ((Get-Date) -lt $endTime) {
        try {
            $line = $serial.ReadLine()
            $lineCount++
            Write-Host "[$lineCount] $line" -ForegroundColor White
        }
        catch [System.TimeoutException] {
            Write-Host "." -NoNewline -ForegroundColor DarkGray
        }
    }
    
    $serial.Close()
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Прочитано $lineCount строк" -ForegroundColor Green
    
} catch {
    Write-Host "ОШИБКА: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Возможные причины:" -ForegroundColor Yellow
    Write-Host "1. Порт занят другой программой" -ForegroundColor Yellow
    Write-Host "2. Датчик не подключен" -ForegroundColor Yellow
    Write-Host "3. Неправильный номер порта" -ForegroundColor Yellow
}
