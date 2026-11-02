@echo off
setlocal EnableExtensions
title Ejecutar ligas de baloncesto
call "%~dp0..\scripts\config.bat"

rem Uso: LIGAS_RESULTADOS.bat              (menu)
rem      LIGAS_RESULTADOS.bat <argumentos>  (todas las ligas, argumentos para EJECUTAR_TODAS_LAS_LIGAS.ps1)
if not "%~1"=="" goto :run_all

echo.
echo ============================================================
echo  RESULTADOS DE BALONCESTO
echo ============================================================
echo  [1] Ejecutar todas las ligas del JSON
echo  [2] Elegir una liga concreta
echo.
choice /c 12 /n /m "Selecciona una opcion"
if errorlevel 2 goto :run_one
goto :run_all

:run_one
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres launcher
if errorlevel 1 goto :error

echo.
echo Ligas disponibles:
%PS% -File "%SCRIPTS%\ligas\EJECUTAR_LIGA_BASKET.ps1"
exit /b %ERRORLEVEL%

:run_all
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres launcher
if errorlevel 1 goto :error

echo [INFO] Lanzando el proceso para todas las ligas...
%PS% -File "%SCRIPTS%\ligas\EJECUTAR_TODAS_LAS_LIGAS.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo [ERROR] El proceso termino con errores.
) else (
    echo [OK] Proceso finalizado.
)
echo.
pause
exit /b %EXIT_CODE%

:error
echo.
echo ERROR: No se pudieron iniciar los requisitos de ejecucion.
pause
exit /b 1
