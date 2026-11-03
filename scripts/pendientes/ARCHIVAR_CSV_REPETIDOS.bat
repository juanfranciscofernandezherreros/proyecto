@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"

rem Deja un unico CSV vigente (el mas reciente) por carpeta y dataset y mueve los anteriores
rem al historico, fuera de las carpetas que vigila el launcher.
rem Uso: ARCHIVAR_CSV_REPETIDOS.bat            (simulacion: solo lista lo que moveria)
rem      ARCHIVAR_CSV_REPETIDOS.bat aplicar    (los mueve)
if /i "%~1"=="aplicar" (
    %PS% -File "%~dp0ARCHIVAR_CSV_REPETIDOS.ps1" -Aplicar
) else (
    %PS% -File "%~dp0ARCHIVAR_CSV_REPETIDOS.ps1"
)
exit /b %ERRORLEVEL%
