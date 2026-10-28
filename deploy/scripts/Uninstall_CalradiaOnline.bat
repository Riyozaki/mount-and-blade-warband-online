@echo off
chcp 65001 >nul
echo ====================================================================
echo   Calradia Online — Полное удаление мода
echo ====================================================================
"%~dp0calradia_installer.exe" uninstall
echo.
pause
