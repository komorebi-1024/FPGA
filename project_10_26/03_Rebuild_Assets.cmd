@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\workflow.ps1" -Action Assets
if errorlevel 1 echo FAILED: inspect the log.
pause
