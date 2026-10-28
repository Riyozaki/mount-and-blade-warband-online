@echo off
chcp 65001 >nul
echo ====================================================================
echo   Calradia Online — Чистое обновление (удаление старых файлов + сохранение сейвов)
echo ====================================================================
"%~dp0calradia_installer.exe" update --package "%~dp0CalradiaOnlinePackage" --version 1.0.0
echo.
pause
