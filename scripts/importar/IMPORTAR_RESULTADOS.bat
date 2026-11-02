@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"

rem Uso: IMPORTAR_RESULTADOS.bat <csv_resultados> <pais> <competicion>
if "%~1"=="" (
    echo ERROR: Falta la ruta del CSV de resultados.
    exit /b 1
)
if "%~2"=="" (
    echo ERROR: Falta el pais de la competicion.
    exit /b 1
)
if "%~3"=="" (
    echo ERROR: Falta la competicion.
    exit /b 1
)

call "%SCRIPTS%\arranque\ASEGURAR.bat" postgres launcher || exit /b 1
%PS% -File "%SCRIPTS%\importar\IMPORTAR_RESULTADOS_EUROLIGA_A_POSTGRESQL.ps1" -CsvPath "%~1" -Country "%~2" -Competition "%~3"
exit /b %ERRORLEVEL%
