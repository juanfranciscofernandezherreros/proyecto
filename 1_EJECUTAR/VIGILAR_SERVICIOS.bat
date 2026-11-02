@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

rem Vigilante: cada [minutos] comprueba los servicios y arranca los que esten parados.
rem Uso: VIGILAR_SERVICIOS.bat [minutos] [servicio...]
rem   Por defecto: cada 5 minutos -> antibloqueo postgres auditoria launcher grafana
rem   Una sola pasada (para la tarea programada o pruebas): VIGILAR_SERVICIOS.bat una-vez
rem Registro: %REPORT_DIR%\vigilancia-servicios.log
set "INTERVAL=%~1"
set "ONCE="
if /i "%INTERVAL%"=="una-vez" (
    set "ONCE=1"
    set "INTERVAL=5"
)
if not defined INTERVAL set "INTERVAL=5"
call "%SCRIPTS%\validar_limite.bat" "%INTERVAL%" || exit /b 1
if "%INTERVAL%"=="0" set "INTERVAL=1"

shift
set "SERVICES=%~1 %~2 %~3 %~4 %~5 %~6 %~7"
if "%~1"=="" set "SERVICES=antibloqueo postgres auditoria launcher grafana"

if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
set "LOG=%REPORT_DIR%\vigilancia-servicios.log"
set "LAST=%TEMP%\vigilancia-servicios-%RANDOM%.txt"

if defined ONCE goto check

rem Una sola instancia: si ya hay un vigilante abierto, no se abre otro.
tasklist /v /fi "IMAGENAME eq cmd.exe" /fi "WINDOWTITLE eq Vigilante de servicios Basketball*" /fo csv /nh | findstr /i /c:"Vigilante de servicios Basketball" >nul
if not errorlevel 1 (
    echo El vigilante de servicios ya esta en ejecucion.
    exit /b 0
)
title Vigilante de servicios Basketball
echo Vigilando cada %INTERVAL% min: %SERVICES%
echo Registro: %LOG%
echo Cierra esta ventana para detener la vigilancia.

:check
echo.
echo [%DATE% %TIME:~0,8%] Comprobando servicios...
call "%SCRIPTS%\arranque\ASEGURAR.bat" %SERVICES% > "%LAST%" 2>&1
set "RESULT=%ERRORLEVEL%"
type "%LAST%"
rem Solo se registra cuando hubo que arrancar algo o algo fallo, para que el log sea util.
findstr /i /c:"arrancando" /c:"reiniciando" /c:"ERROR" "%LAST%" >nul
if not errorlevel 1 (
    >> "%LOG%" echo [%DATE% %TIME:~0,8%] codigo %RESULT%
    >> "%LOG%" type "%LAST%"
)
del "%LAST%" >nul 2>&1
if defined ONCE exit /b %RESULT%

set /a WAIT_SECONDS=INTERVAL*60+1
ping 127.0.0.1 -n %WAIT_SECONDS% >nul
goto check
