@echo off
:: Этот файл запускает fix_usb.ps1 с правами администратора
:: Просто запустите этот файл двойным кликом

echo Zapros prav administratora...
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& {Start-Process PowerShell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0fix_usb.ps1""' -Verb RunAs}"
