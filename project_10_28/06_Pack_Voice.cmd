@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\workflow.ps1" -Action Voice
if errorlevel 1 echo FAILED: inspect the error before using the voice image.
pause
