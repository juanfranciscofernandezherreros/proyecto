@echo off
setlocal EnableExtensions
title Procesar ultimos partidos de baloncesto
call "%~dp0..\scripts\config.bat"

call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres launcher
if errorlevel 1 exit /b %ERRORLEVEL%

%PS% -File "%SCRIPTS%\ligas\PROCESAR_ULTIMOS_PARTIDOS_COMPLETO.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (echo [OK] Flujo completo terminado.) else (echo [ERROR] Flujo terminado con errores.)
pause
exit /b %EXIT_CODE%
