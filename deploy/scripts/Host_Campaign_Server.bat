@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title Calradia Online — Хост кампании

rem ==================================================================
rem  Запуск хоста кооперативной кампании (один щелчок):
rem    1. campaign-сервер WSE2           (внутренний порт 7241)
rem    2. боевые серверы WSE2 (2 слота)   (внутренние порты 7242, 7244)
rem    3. CoopHostSupervisor — единый публичный UDP-шлюз (порт 7240)
rem  Игрокам нужен открыть ТОЛЬКО UDP 7240 (или подключиться по VPN).
rem ==================================================================

set "HERE=%~dp0"
set "PUBLIC_PORT=7240"
set "BATTLE_SLOTS=2"

rem --- Поиск папки Mount & Blade Warband (через установщик рядом) ---
set "WB="
for /f "delims=" %%i in ('""%HERE%calradia_installer.exe" detect 2^>nul"') do (
    if not defined WB set "WB=%%i"
)
if not defined WB (
    echo [?] Папка Warband не найдена автоматически.
    set /p "WB=Введите полный путь к папке Mount & Blade Warband: "
)
set "HAS_GAME=0"
if exist "%WB%\mb_warband.exe" set "HAS_GAME=1"
if exist "%WB%\mb_warband_wse2.exe" set "HAS_GAME=1"
if "%HAS_GAME%"=="0" (
    echo [!] В папке "%WB%" нет mb_warband.exe. Проверьте путь.
    pause
    exit /b 1
)

rem --- Проверка WSE2 dedicated (нужен для сервера) ---
if not exist "%WB%\mb_warband_wse2_dedicated_campaign.exe" (
    echo [!] Не найден mb_warband_wse2_dedicated_campaign.exe.
    echo     Установите Warband Script Enhancer 2 в папку игры и повторите запуск.
    pause & exit /b 1
)

set "MOD=%WB%\Modules\CalradiaOnline"
if not exist "%MOD%\install_manifest.json" (
    echo [!] Мод не установлен. Сначала запустите Install_CalradiaOnline.bat.
    pause & exit /b 1
)

set /a LAST_SLOT=%BATTLE_SLOTS%-1

echo ====================================================================
echo   Calradia Online — запуск хоста
echo   Игроки подключаются к этому ПК на UDP порт %PUBLIC_PORT%
echo ====================================================================

echo [1/3] Запуск campaign-сервера...
start "Calradia Campaign" /D "%WB%" /MIN mb_warband_wse2_dedicated_campaign.exe -r "Modules\CalradiaOnline\dedicated_campaign_server.txt" --module CalradiaOnline
timeout /t 3 /nobreak >nul

echo [2/3] Запуск боевых серверов (%BATTLE_SLOTS% слота)...
for /L %%s in (0,1,%LAST_SLOT%) do (
    start "Calradia Battle %%s" /D "%WB%" /MIN mb_warband_wse2_dedicated.exe -r "Modules\CalradiaOnline\battle_server_slot%%s.txt" --module CalradiaOnline
)
timeout /t 3 /nobreak >nul

echo [3/3] Запуск шлюза CoopHostSupervisor...
start "Calradia Gateway" /D "%MOD%" /MIN "%MOD%\bin\coop_host_supervisor.exe" --port %PUBLIC_PORT% --pool-size %BATTLE_SLOTS% --spool-dir saves\ipc

echo.
echo Хост запущен. Окна серверов свернуты на панель задач.
echo Чтобы остановить хост, закройте окна "Calradia Campaign", "Calradia Battle N", "Calradia Gateway".
echo.
pause
