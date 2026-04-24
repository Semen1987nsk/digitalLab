$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $projectRoot

$buildDir = Join-Path $projectRoot "build\windows\x64\runner\Release"
$distDir = Join-Path $projectRoot "dist\Labosfera"
$zipPath = Join-Path $projectRoot "dist\Labosfera_Windows_x64.zip"

$launcherPath = Join-Path $distDir "ЗАПУСК.bat"
$runtimeInstallerPath = Join-Path $distDir "УСТАНОВИТЬ_VC_RUNTIME.bat"
$readmePath = Join-Path $distDir "ПРОЧТИМЕНЯ.txt"

if (-not (Test-Path (Join-Path $buildDir "digital_lab.exe"))) {
    throw "Release build not found. Run 'flutter build windows --release' first."
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LABOSFERA: packaging Windows release" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $distDir) {
    Write-Host "[1/5] Clearing previous dist folder..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $distDir -Recurse -Force
}

Write-Host "[1/5] Copying release build..." -ForegroundColor Green
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Copy-Item -Path (Join-Path $buildDir "*") -Destination $distDir -Recurse -Force

Write-Host "[2/5] Bundling VC++ runtime DLLs..." -ForegroundColor Green
$vcDlls = @(
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "msvcp140.dll",
    "msvcp140_1.dll",
    "msvcp140_2.dll"
)
$systemDir = "C:\Windows\System32"
$bundledCount = 0

foreach ($dll in $vcDlls) {
    $sourcePath = Join-Path $systemDir $dll
    if (Test-Path $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $distDir $dll) -Force
        $bundledCount++
        Write-Host "  + $dll" -ForegroundColor DarkGreen
    } else {
        Write-Host "  - $dll not found in System32" -ForegroundColor DarkYellow
    }
}

Write-Host "[3/5] Creating launcher..." -ForegroundColor Green
$launcherBat = @'
@echo off
chcp 65001 >nul 2>&1
title LABOSFERA - Цифровая лаборатория по физике
echo.
echo  ========================================
echo   LABOSFERA v2.0
echo   Цифровая лаборатория по физике
echo  ========================================
echo.
echo  Запуск приложения...
echo.
start "" "%~dp0digital_lab.exe"
'@
Set-Content -LiteralPath $launcherPath -Value $launcherBat -Encoding UTF8

Write-Host "[4/5] Creating VC++ runtime installer helper..." -ForegroundColor Green
$runtimeInstallerBat = @'
@echo off
chcp 65001 >nul 2>&1
echo.
echo  ========================================
echo   Установка Visual C++ Runtime
echo  ========================================
echo.
echo  Этот скрипт нужен только если приложение
echo  не запускается с ошибкой про vcruntime140.dll.
echo.
where curl >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo curl не найден. Скачайте вручную:
    echo https://aka.ms/vs/17/release/vc_redist.x64.exe
    pause
    exit /b 1
)

curl -L -o "%TEMP%\vc_redist.x64.exe" "https://aka.ms/vs/17/release/vc_redist.x64.exe"
if %ERRORLEVEL% NEQ 0 (
    echo Не удалось скачать VC++ Runtime.
    echo Прямая ссылка: https://aka.ms/vs/17/release/vc_redist.x64.exe
    pause
    exit /b 1
)

echo.
echo Запуск установщика...
"%TEMP%\vc_redist.x64.exe" /install /quiet /norestart
echo.
echo Готово. Теперь запустите ЗАПУСК.bat.
echo.
pause
'@
Set-Content -LiteralPath $runtimeInstallerPath -Value $runtimeInstallerBat -Encoding UTF8

Write-Host "[5/5] Creating README and ZIP..." -ForegroundColor Green
$readme = @'
LABOSFERA v2.0
Цифровая лаборатория по физике

БЫСТРЫЙ СТАРТ
1. Распакуйте архив в любую папку.
2. Запустите "ЗАПУСК.bat" или "digital_lab.exe".
3. Если Windows ругается на отсутствующий runtime, запустите
   "УСТАНОВИТЬ_VC_RUNTIME.bat" от имени администратора.

ЧТО ВНУТРИ
- digital_lab.exe: основная программа
- data/: данные приложения
- *.dll: системные и Flutter-библиотеки
- ЗАПУСК.bat: удобный запуск
- УСТАНОВИТЬ_VC_RUNTIME.bat: помощь с VC++ runtime

ТРЕБОВАНИЯ
- Windows 10/11 x64
- 4 GB RAM или больше
- около 100 MB свободного места
'@
Set-Content -LiteralPath $readmePath -Value $readme -Encoding UTF8

if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path $distDir -DestinationPath $zipPath -CompressionLevel Optimal

$fileCount = (Get-ChildItem -LiteralPath $distDir -Recurse -File).Count
$totalSizeMb = [math]::Round(((Get-ChildItem -LiteralPath $distDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
$zipSizeMb = [math]::Round(((Get-Item -LiteralPath $zipPath).Length / 1MB), 1)

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Distribution package is ready" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Folder: $distDir" -ForegroundColor White
Write-Host "ZIP:    $zipPath ($zipSizeMb MB)" -ForegroundColor White
Write-Host "Files:  $fileCount" -ForegroundColor White
Write-Host "Size:   $totalSizeMb MB" -ForegroundColor White
Write-Host "VC++ DLLs bundled: $bundledCount" -ForegroundColor White
Write-Host ""
