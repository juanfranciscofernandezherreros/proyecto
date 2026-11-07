@echo off
setlocal EnableExtensions
title Basketball - extraer RESULTADOS
rem =============================================================================
rem Extrae los RESULTS (marcadores + parciales) descrito en ESPECIFICACIONES.md 5.
rem Envoltorio de LIGAS_ORQUESTAR.bat en modo "results".
rem
rem Uso: EXTRAER_RESULTADOS.bat [LIGA] [limite]
rem   LIGA   = ALL (por defecto) | EUROLIGA | ACB | NBA | BSL | GBL | LEGA_A |
rem            LNB | BBL | LKL | KLS | WINNER        (ver LIGAS_BASKET.json)
rem   limite = nº de partidos (opcional)
rem Ejemplos:
rem   EXTRAER_RESULTADOS.bat                 (todas las ligas)
rem   EXTRAER_RESULTADOS.bat EUROLIGA
rem   EXTRAER_RESULTADOS.bat EUROLIGA 10
rem =============================================================================
set "LIGA=%~1"
if "%LIGA%"=="" set "LIGA=ALL"
set "LIMITE=%~2"

echo Extrayendo RESULTS de %LIGA% (limite: %LIMITE%)...
call "%~dp0LIGAS_ORQUESTAR.bat" %LIGA% results %LIMITE%
set "RC=%ERRORLEVEL%"
echo.
echo Terminado con codigo %RC%. Los marcadores se cargan en Postgres (results.results).
endlocal & exit /b %RC%
