@echo off
chcp 65001 >nul
echo ====================================================================
echo   Calradia Online — Автоматическая установка мода
echo ====================================================================
"%~dp0calradia_installer.exe" install --package "%~dp0CalradiaOnlinePackage" --version 1.0.0
echo.
pause
