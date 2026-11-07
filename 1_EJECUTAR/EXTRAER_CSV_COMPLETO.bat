@echo off
setlocal EnableExtensions
title Basketball - extraer resto de CSV y procesar pendientes
rem =============================================================================
rem Extrae el resto de CSV (point-by-point, team-stats, player-stats) y luego
rem procesa los partidos pendientes. Cubre ESPECIFICACIONES.md 6 y 7.
rem   1) LIGAS_ORQUESTAR.bat <LIGA> datos  -> extrae el detalle.
rem   2) MATCHIDS_PENDIENTES.bat           -> completa lo que falte de cada partido.
rem
rem Uso: EXTRAER_CSV_COMPLETO.bat [LIGA] [limite]
rem   LIGA   = ALL (por defecto) | EUROLIGA | ACB | NBA | ...  (LIGAS_BASKET.json)
rem   limite = nº de partidos (opcional)
rem Ejemplos:
rem   EXTRAER_CSV_COMPLETO.bat
rem   EXTRAER_CSV_COMPLETO.bat EUROLIGA 10
rem =============================================================================
set "LIGA=%~1"
if "%LIGA%"=="" set "LIGA=ALL"
set "LIMITE=%~2"

echo.
echo === 1) Extraer datos (point-by-point, team-stats, player-stats) de %LIGA% ===
call "%~dp0LIGAS_ORQUESTAR.bat" %LIGA% datos %LIMITE%
if errorlevel 1 echo [AVISO] La extraccion de datos devolvio error; se continua con los pendientes.

echo.
echo === 2) Procesar partidos pendientes ===
call "%~dp0MATCHIDS_PENDIENTES.bat"
set "RC=%ERRORLEVEL%"
echo.
echo Terminado con codigo %RC%.
endlocal & exit /b %RC%
