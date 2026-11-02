@echo off
setlocal EnableExtensions
title Importar TEAM_STATS a PostgreSQL
call "%~dp0..\config.bat"

rem Uso: IMPORTAR_TEAM_STATS.bat [pais] [competicion]
set "COUNTRY=%~1"
set "COMPETITION=%~2"
if not defined COUNTRY set "COUNTRY=europe"
if not defined COMPETITION set "COMPETITION=euroleague"

call "%SCRIPTS%\arranque\ASEGURAR.bat" postgres launcher || exit /b 1
%PS% -File "%SCRIPTS%\importar\PROCESAR_TEAM_STATS_EUROLIGA_A_POSTGRESQL.ps1" -Country "%COUNTRY%" -Competition "%COMPETITION%"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
    echo [ERROR] Importacion TEAM_STATS fallida.
) else (
    echo [OK] TEAM_STATS importado en PostgreSQL.
)
exit /b %EXIT_CODE%
