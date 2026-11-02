@echo off
setlocal EnableExtensions
title Basketball - procesamiento automatico
call "%~dp0..\scripts\config.bat"

rem Lo ejecuta la tarea programada al iniciar sesion (scripts\arranque\TAREA_INICIO.bat).
rem 1. Arranca, si estan parados, Docker y todos los servicios del procesamiento.
rem 2. Lo ultimo del arranque: Grafana y el dashboard de pendientes en el navegador.
rem 3. Lanza MATCHIDS_PENDIENTES, que procesa todos los partidos pendientes.
rem Todo queda en %REPORT_DIR%\automatico-inicio-<fecha>.log
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
for /f %%T in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%T"
set "LOG=%REPORT_DIR%\automatico-inicio-%STAMP%.log"

echo Procesamiento automatico iniciado. Registro: %LOG%
>> "%LOG%" echo [%DATE% %TIME:~0,8%] Inicio del procesamiento automatico

rem Los arranques NO se redirigen al log: arrancan procesos de larga duracion (antibloqueo,
rem Java, Docker) que heredarian el fichero abierto y lo dejarian bloqueado, y entonces cmd
rem ya no podria ejecutar las siguientes lineas con ">>". ASEGURAR escribe en el log por su
rem cuenta, linea a linea, gracias a ASEGURAR_LOG.
set "ASEGURAR_LOG=%LOG%"
echo Arrancando Docker y servicios...
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres auditoria launcher
if errorlevel 1 (
    >> "%LOG%" echo [ERROR] No se pudieron arrancar los servicios; no se procesa nada.
    echo ERROR: no se pudieron arrancar los servicios. Registro: %LOG%
    exit /b 1
)

rem Grafana va al final del arranque y no es imprescindible: si falla, se registra y se sigue.
echo Arrancando Grafana...
call "%SCRIPTS%\arranque\ASEGURAR.bat" grafana
if errorlevel 1 (
    >> "%LOG%" echo [AVISO] Grafana no quedo disponible; se continua con el procesamiento.
) else (
    rem Abre el dashboard de pendientes en el navegador para seguir el avance en vivo.
    start "" "%GRAFANA_URL%/d/fixtures-audit-live"
    >> "%LOG%" echo Dashboard abierto en el navegador.
)

rem Aqui los servicios ya estan arrancados, asi que MATCHIDS_PENDIENTES no crea procesos de
rem larga duracion y su salida si se puede redirigir al log.
set "ASEGURAR_LOG="
echo Procesando partidos pendientes...
call "%~dp0MATCHIDS_PENDIENTES.bat" >> "%LOG%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
>> "%LOG%" echo [%DATE% %TIME:~0,8%] Fin del procesamiento automatico. Codigo %EXIT_CODE%
echo Terminado con codigo %EXIT_CODE%. Registro: %LOG%
exit /b %EXIT_CODE%
