@echo off
title Macify Setup
echo Starting Macify installer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install.ps1" %*
echo.
pause
