@echo off
rem Check everything without the window (report in the console).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CoopLauncher.ps1" -SelfTest
pause
