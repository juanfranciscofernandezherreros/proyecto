@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"
rem shift tambien desplaza %0: se guarda la carpeta del script antes del bucle.
set "HERE=%~dp0"

rem Comprueba cada servicio y, si no esta listo, lo arranca y espera a que lo este.
rem Uso: ASEGURAR.bat <servicio> [servicio...] [--reiniciar-launcher] [--actualizar-dashboard]
rem Servicios: antibloqueo watcher docker postgres runtime auditoria launcher grafana navegador consumo
rem SKIP_CSV_WATCHER=1 ignora "watcher".
if "%~1"=="" (
    echo ERROR: indica al menos un servicio: antibloqueo watcher docker postgres runtime auditoria launcher grafana navegador consumo
    exit /b 1
)
set "SERVICES="
set "EXTRA="
:next_arg
if "%~1"=="" goto run
if /i "%~1"=="--reiniciar-launcher" (
    set "EXTRA=%EXTRA% -ReiniciarLauncher"
) else if /i "%~1"=="--actualizar-dashboard" (
    set "EXTRA=%EXTRA% -ActualizarDashboard"
) else if /i "%~1"=="watcher" (
    if /i not "%SKIP_CSV_WATCHER%"=="1" set "SERVICES=%SERVICES%,watcher"
) else (
    set "SERVICES=%SERVICES%,%~1"
)
shift
goto next_arg

:run
rem Solo se pidio el watcher y esta desactivado: no hay nada que asegurar.
if not defined SERVICES exit /b 0
%PS% -File "%HERE%ASEGURAR_SERVICIOS.ps1" -Servicios "%SERVICES:~1%" %EXTRA%
exit /b %ERRORLEVEL%
