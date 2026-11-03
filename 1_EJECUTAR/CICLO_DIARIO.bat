@echo off
setlocal EnableExtensions
title Basketball - ciclo diario
call "%~dp0..\scripts\config.bat"

rem Lo ejecuta cada dia la tarea programada (scripts\arranque\TAREA_DIARIA.bat).
rem 1. Extrae e importa los RESULTS de todas las ligas, para conocer los partidos nuevos.
rem 2. Lanza MATCHIDS_PENDIENTES, que procesa todos los partidos pendientes.
rem 3. Mueve al historico los CSV antiguos (ARCHIVAR_CSV_REPETIDOS).
rem Un fallo en el paso 1 no impide el paso 2: los pendientes anteriores se siguen procesando.
rem Todo queda en %REPORT_DIR%\ciclo-diario-<fecha>.log
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
for /f %%T in ('powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%T"
set "LOG=%REPORT_DIR%\ciclo-diario-%STAMP%.log"

echo Ciclo diario iniciado. Registro: %LOG%
>> "%LOG%" echo [%DATE% %TIME:~0,8%] Inicio del ciclo diario

rem Como en AUTOMATICO_INICIO, el arranque de servicios no se redirige al log.
set "ASEGURAR_LOG=%LOG%"
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres auditoria launcher navegador
if errorlevel 1 (
    >> "%LOG%" echo [ERROR] No se pudieron arrancar los servicios; no se procesa nada.
    exit /b 1
)
set "ASEGURAR_LOG="

>> "%LOG%" echo --- Partidos jugados sin resultado ANTES de RESULTS:
call "%SCRIPTS%\pendientes\FIXTURES_SIN_RESULTS.bat" >> "%LOG%" 2>&1

echo Extrayendo RESULTS de todas las ligas...
call "%~dp0LIGAS_ORQUESTAR.bat" ALL results >> "%LOG%" 2>&1
if errorlevel 1 >> "%LOG%" echo [AVISO] Alguna liga fallo en RESULTS; se continua con los pendientes.

>> "%LOG%" echo --- Partidos jugados sin resultado DESPUES de RESULTS:
call "%SCRIPTS%\pendientes\FIXTURES_SIN_RESULTS.bat" >> "%LOG%" 2>&1

echo Procesando partidos pendientes...
call "%~dp0MATCHIDS_PENDIENTES.bat" >> "%LOG%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

rem Con todo importado, deja un unico CSV vigente por partido y dataset; el resto, al historico.
>> "%LOG%" echo --- Archivado de CSV repetidos:
call "%SCRIPTS%\pendientes\ARCHIVAR_CSV_REPETIDOS.bat" aplicar >> "%LOG%" 2>&1
>> "%LOG%" echo [%DATE% %TIME:~0,8%] Fin del ciclo diario. Codigo %EXIT_CODE%
echo Terminado con codigo %EXIT_CODE%. Registro: %LOG%
exit /b %EXIT_CODE%
