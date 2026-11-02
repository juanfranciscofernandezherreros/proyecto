@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"

rem Uso interno: EXTRAER_DATASET.bat <etiqueta> <dataset.csv> [pais] [competicion] [limite]
set "LABEL=%~1"
set "DATASET=%~2"
set "COUNTRY=%~3"
set "COMPETITION=%~4"
set "LIMIT=%~5"
if not defined COUNTRY set "COUNTRY=europe"
if not defined COMPETITION set "COMPETITION=euroleague"
if not defined LIMIT set "LIMIT=20"
call "%~dp0..\validar_limite.bat" "%LIMIT%" || exit /b 1

title Extraer CSV %LABEL%
echo Extrayendo %LABEL% desde el ultimo RESULTS CSV: %COUNTRY%/%COMPETITION%
%PS% -File "%SCRIPTS%\extraer\EXTRAER_DATASET_PENDIENTE.ps1" -Dataset %DATASET% -Country "%COUNTRY%" -Competition "%COMPETITION%" -Limit %LIMIT%
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" echo [ERROR] Extraccion %LABEL% fallida.
exit /b %EXIT_CODE%
