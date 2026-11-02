@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"

rem Tarea programada que, al iniciar sesion, ejecuta 1_EJECUTAR\AUTOMATICO_INICIO.bat
rem (arranca Docker y servicios si estan parados y procesa los partidos pendientes).
rem Uso: TAREA_INICIO.bat instalar [minutos_de_espera] ^| quitar ^| estado ^| ejecutar
if "%~1"=="" (
    echo Uso: TAREA_INICIO.bat instalar [minutos_de_espera] ^| quitar ^| estado ^| ejecutar
    exit /b 1
)
if "%~2"=="" (
    %PS% -File "%~dp0TAREA_INICIO.ps1" -Accion %~1
) else (
    %PS% -File "%~dp0TAREA_INICIO.ps1" -Accion %~1 -RetrasoMinutos %~2
)
exit /b %ERRORLEVEL%
