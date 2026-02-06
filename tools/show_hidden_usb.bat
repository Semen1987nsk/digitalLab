@echo off
:: Показывает скрытые USB устройства в Диспетчере устройств
:: Удалите все серые (неактивные) устройства VID_0000

set devmgr_show_nonpresent_devices=1
start devmgmt.msc

echo.
echo V Dispetchere ustrojstv:
echo   Vid -^> Pokazat' skrytye ustrojstva
echo   Udalite vse SERYE ustrojstva v razdele "Kontrollery USB"
echo.
pause
