@echo off
setlocal EnableExtensions
title Basketball - procesar CSV de RESULTADOS
rem =============================================================================
rem Procesa los CSV de RESULTS que ya estan en disco y los carga en Postgres
rem (results.results). NO extrae nada de Flashscore: para eso, EXTRAER_RESULTADOS.bat.
rem
rem Uso: PROCESAR_CSV_RESULTADOS.bat [LIGA] [todos]
rem   LIGA  = ALL (por defecto) | EUROLIGA | ACB | NBA | ...   (ver LIGAS_BASKET.json)
rem   todos = importa todos los CSV de cada liga, del mas antiguo al mas reciente.
rem           Sin el, solo el mas reciente de cada liga (contiene a los anteriores).
rem Ejemplos:
rem   PROCESAR_CSV_RESULTADOS.bat
rem   PROCESAR_CSV_RESULTADOS.bat EUROLIGA
rem   PROCESAR_CSV_RESULTADOS.bat ALL todos
rem =============================================================================
call "%~dp0..\scripts\config.bat" || exit /b 1
set "LIGA=%~1"
if "%LIGA%"=="" set "LIGA=ALL"
set "EXTRA="
if /i "%~2"=="todos" set "EXTRA=-Todos"

call "%SCRIPTS%\arranque\ASEGURAR.bat" postgres launcher || exit /b 1
%PS% -File "%SCRIPTS%\importar\IMPORTAR_RESULTADOS_TODAS.ps1" -League "%LIGA%" %EXTRA%
exit /b %ERRORLEVEL%
