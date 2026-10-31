@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\workflow.ps1" -Action Audio
if errorlevel 1 echo FAILED: inspect the error before writing the SD card.
pause
