@echo off
setlocal EnableExtensions
title Flujo de datos Euroliga
call "%~dp0..\scripts\config.bat"

rem Uso: DATOS_EUROLIGA.bat [pais] [competicion] [limite]
set "COUNTRY=%~1"
set "COMPETITION=%~2"
set "LIMIT=%~3"
if not defined COUNTRY set "COUNTRY=europe"
if not defined COMPETITION set "COMPETITION=euroleague"
if not defined LIMIT set "LIMIT=10"
call "%SCRIPTS%\validar_limite.bat" "%LIMIT%" || exit /b 1

echo.
echo ============================================================
echo  FLUJO EUROLIGA: %COUNTRY% / %COMPETITION%  (%LIMIT% partidos)
echo ============================================================
echo  [1] POINT_BY_POINT: extraer e importar
echo  [2] TEAM_STATS: extraer e importar
echo  [3] PLAYER_STATS: extraer e importar
echo  [4] Todo: PBP + equipo + jugadores
echo  [0] Salir
echo.
choice /c 12340 /n /m "Selecciona una opcion"
if errorlevel 5 exit /b 0
if errorlevel 4 goto :all
if errorlevel 3 goto :players
if errorlevel 2 goto :team_stats
if errorlevel 1 goto :point_by_point

:preflight
if defined AUXILIARIES_STARTED exit /b 0
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo watcher postgres launcher navegador || exit /b 1
set "AUXILIARIES_STARTED=1"
exit /b 0

:point_by_point
call :preflight || exit /b 1
call "%SCRIPTS%\extraer\EXTRAER_POINT_BY_POINT.bat" "%COUNTRY%" "%COMPETITION%" %LIMIT% || exit /b 1
call "%SCRIPTS%\importar\IMPORTAR_POINT_BY_POINT.bat" "%COUNTRY%" "%COMPETITION%"
exit /b %ERRORLEVEL%

:team_stats
call :preflight || exit /b 1
call "%SCRIPTS%\extraer\EXTRAER_TEAM_STATS.bat" "%COUNTRY%" "%COMPETITION%" %LIMIT% || exit /b 1
call "%SCRIPTS%\importar\IMPORTAR_TEAM_STATS.bat" "%COUNTRY%" "%COMPETITION%"
exit /b %ERRORLEVEL%

:players
call :preflight || exit /b 1
call "%SCRIPTS%\extraer\EXTRAER_PLAYER_STATS.bat" "%COUNTRY%" "%COMPETITION%" %LIMIT% || exit /b 1
call "%SCRIPTS%\importar\IMPORTAR_PLAYER_STATS.bat" "%COUNTRY%" "%COMPETITION%"
exit /b %ERRORLEVEL%

:all
call :point_by_point || exit /b 1
call :team_stats || exit /b 1
call :players
exit /b %ERRORLEVEL%
