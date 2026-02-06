@echo off
:: FINAL USB FIX - Reset Windows USB Stack
:: Run as Administrator!
echo.
echo =============================================
echo  FINALNIY SBROS USB STEKA WINDOWS
echo =============================================
echo.

:: Check admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo OSHIBKA: Zapustite ot imeni Administratora!
    pause
    exit /b
)

echo [1/5] Udalyaem VSE problemnye VID_0000 ustrojstva...
pnputil /remove-device "USB\VID_0000&PID_0002\6&4B0179&0&1" 2>nul
pnputil /remove-device "USB\VID_0000&PID_0002\6&4B0179&0&2" 2>nul
pnputil /remove-device "USB\VID_0000&PID_0002\6&2C3E714&0&2" 2>nul
pnputil /remove-device "USB\VID_0000&PID_0002\6&2C3E714&0&3" 2>nul
pnputil /remove-device "USB\VID_0000&PID_0002\6&2C3E714&0&8" 2>nul

echo [2/5] Sbros USB drajverov...
net stop usbhub3 2>nul
net start usbhub3 2>nul

echo [3/5] Otklyuchaem Selective Suspend cherez reestr...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB" /v "DisableSelectiveSuspend" /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\USBXHCI" /v "DisableSelectiveSuspend" /t REG_DWORD /d 1 /f

echo [4/5] Vklyuchaem Renesas obratno...
pnputil /enable-device "PCI\VEN_1033&DEV_0194&SUBSYS_70011B5B&REV_03\FFFFFFFFFFFFFFFF00" 2>nul

echo [5/5] Polnoe skanirovanie ustrojstv...
pnputil /scan-devices

echo.
echo =============================================
echo  GOTOVO!
echo  Teper:
echo  1. VYKLYUCHITE komputer (ne perezagruzka!)
echo  2. Vyderzhite 30 sekund
echo  3. Vklyuchite komputer
echo  4. Podklyuchite Arduino
echo =============================================
echo.
pause
