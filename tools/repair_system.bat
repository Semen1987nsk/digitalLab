@echo off
:: Запускает sfc /scannow и DISM для восстановления системных файлов USB
:: Требует права Администратора!

echo.
echo =============================================
echo  PROVERKA I VOSSTANOVLENIE SISTEMNYH FAJLOV
echo =============================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo OSHIBKA: Zapustite ot imeni Administratora!
    pause
    exit /b
)

echo [1/2] DISM - vosstanovlenie hranlishcha komponentov...
DISM /Online /Cleanup-Image /RestoreHealth

echo.
echo [2/2] SFC - proverka sistemnyh fajlov...
sfc /scannow

echo.
echo =============================================
echo  GOTOVO! Perezagruzite komputer i 
echo  podklyuchite Arduino NAPRIAMUYU (bez haba)
echo =============================================
echo.
pause
