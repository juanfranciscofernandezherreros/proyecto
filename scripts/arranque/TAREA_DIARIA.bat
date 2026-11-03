@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"

rem Tarea programada que cada dia ejecuta 1_EJECUTAR\CICLO_DIARIO.bat
rem (RESULTS de todas las ligas y despues los partidos pendientes).
rem Uso: TAREA_DIARIA.bat instalar [HH:mm] ^| quitar ^| estado ^| ejecutar
if "%~1"=="" (
    echo Uso: TAREA_DIARIA.bat instalar [HH:mm] ^| quitar ^| estado ^| ejecutar
    exit /b 1
)
if "%~2"=="" (
    %PS% -File "%~dp0TAREA_DIARIA.ps1" -Accion %~1
) else (
    %PS% -File "%~dp0TAREA_DIARIA.ps1" -Accion %~1 -Hora %~2
)
exit /b %ERRORLEVEL%
