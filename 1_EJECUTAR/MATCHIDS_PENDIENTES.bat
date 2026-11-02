@echo off
setlocal EnableExtensions
title Procesar partidos pendientes desde auditoria fresca
call "%~dp0..\scripts\config.bat"

rem Uso: MATCHIDS_PENDIENTES.bat [csv_de_seleccion_opcional] [limite]
rem Los monitores interactivos se omiten: no hacen falta para extraer o importar.
set "SKIP_CSV_WATCHER=1"
if not "%~2"=="" call "%SCRIPTS%\validar_limite.bat" "%~2" || exit /b 1

call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres auditoria launcher
if errorlevel 1 (
  echo ERROR: no se pudieron asegurar los servicios necesarios.
  exit /b 1
)

rem Cada ejecucion consulta la auditoria global de nuevo y procesa solo los matchId pendientes.
echo El proceso refrescara la auditoria antes de empezar y despues de cada partido.
if "%~2"=="" (
  %PS% -File "%SCRIPTS%\pendientes\PROCESAR_MATCHIDS_PENDIENTES.ps1" -CsvPath "%~1"
) else (
  %PS% -File "%SCRIPTS%\pendientes\PROCESAR_MATCHIDS_PENDIENTES.ps1" -CsvPath "%~1" -Limit %~2
)
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
  echo ERROR: el procesamiento termino con codigo %EXIT_CODE%.
) else (
  echo Procesamiento terminado. Consulta el CSV de resumen generado en %REPORT_DIR%.
)
exit /b %EXIT_CODE%
