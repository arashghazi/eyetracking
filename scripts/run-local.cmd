@echo off
rem Runs the EyeTracking apps on this computer. Options: see scripts\run-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-local.ps1" %*
if errorlevel 1 pause
