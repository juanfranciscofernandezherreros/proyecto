@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"

rem Registra el vigilante de servicios como tarea programada de Windows: arranca
rem minimizado al iniciar sesion y vuelve a arrancar los servicios que se paren.
rem Uso: TAREA_VIGILANCIA.bat instalar [minutos] ^| quitar ^| estado
if "%~1"=="" (
    echo Uso: TAREA_VIGILANCIA.bat instalar [minutos] ^| quitar ^| estado
    exit /b 1
)
if "%~2"=="" (
    %PS% -File "%~dp0TAREA_VIGILANCIA.ps1" -Accion %~1
) else (
    %PS% -File "%~dp0TAREA_VIGILANCIA.ps1" -Accion %~1 -Minutos %~2
)
exit /b %ERRORLEVEL%
