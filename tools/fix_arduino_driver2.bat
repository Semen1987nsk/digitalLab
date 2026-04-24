@echo off
set SCRIPT_DIR=%~dp0
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%repair_arduino_ports.ps1" -Repair -RemoveGhosts
pause
