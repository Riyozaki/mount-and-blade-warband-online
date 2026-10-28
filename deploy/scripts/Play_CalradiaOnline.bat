@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title Calradia Online — Игра

rem ==================================================================
rem  Запуск игрока (один щелчок): готовит профиль identity.key и
rem  запускает Warband + WSE2 с модулем CalradiaOnline.
rem ==================================================================

set "HERE=%~dp0"

set "WB="
for /f "delims=" %%i in ('""%HERE%calradia_installer.exe" detect 2^>nul"') do (
    if not defined WB set "WB=%%i"
)
if not defined WB (
    echo [?] Папка Warband не найдена автоматически.
    set /p "WB=Введите полный путь к папке Mount & Blade Warband: "
)
if not exist "%WB%\mb_warband_wse2.exe" (
    echo [!] Не найден mb_warband_wse2.exe в "%WB%".
    echo     Установите Warband Script Enhancer 2 и повторите запуск.
    pause & exit /b 1
)

set "MOD=%WB%\Modules\CalradiaOnline"
if not exist "%MOD%\install_manifest.json" (
    echo [!] Мод не установлен. Сначала запустите Install_CalradiaOnline.bat.
    pause & exit /b 1
)

set "NICK="
set /p "NICK=Ваш никнейм в игре: "
if not defined NICK set "NICK=Adventurer"

rem Создать/загрузить identity.key и launcher_config.json (ник сохраняется в профиле)
"%MOD%\bin\calradia_launcher.exe" --mod-dir "%MOD%" --nick "%NICK%" --init-profile
if errorlevel 1 (
    echo [!] Не удалось подготовить профиль игрока.
    pause & exit /b 1
)

echo.
echo Запуск Warband...
echo В игре выберите Multiplayer -^> Join a Campaign и введите адрес хоста
echo (IP:7240 — для LAN/VPN/прямого подключения).
echo.
start "Mount & Blade Warband" /D "%WB%" mb_warband_wse2.exe --module CalradiaOnline --no-intro
exit /b 0
