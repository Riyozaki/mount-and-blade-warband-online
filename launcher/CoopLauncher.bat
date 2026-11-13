@echo off
rem Warband Coop Campaign launcher: double-click this file.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0CoopLauncher.ps1" %*
