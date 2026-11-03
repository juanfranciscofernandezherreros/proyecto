@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

rem Uso: LIGAS_ORQUESTAR.bat [ALL|EUROLIGA|NBA|ACB|...] [results|datos|todo] [limite]
set "LEAGUE=%~1"
set "MODE=%~2"
set "LIMIT=%~3"
if not defined LEAGUE set "LEAGUE=ALL"
if not defined MODE set "MODE=todo"
if not defined LIMIT set "LIMIT=10"
call "%SCRIPTS%\validar_limite.bat" "%LIMIT%" || exit /b 1
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres launcher navegador || exit /b 1

%PS% -File "%SCRIPTS%\ligas\ORQUESTAR_LIGAS.ps1" -League "%LEAGUE%" -Mode "%MODE%" -Limit %LIMIT%
exit /b %ERRORLEVEL%
