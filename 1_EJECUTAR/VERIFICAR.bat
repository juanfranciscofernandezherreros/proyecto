@echo off
setlocal EnableExtensions
title Basketball - verificar (SDD)
rem Verificacion ejecutable del sistema ligada al SDD (docs/VERIFICACION-SDD.md).
rem Requiere el stack arrancado (ARRANCAR_TODO.bat). Codigo de salida 0=verde, 1=rojo.
call "%~dp0..\scripts\config.bat" || exit /b 1
%PS% -File "%SCRIPTS%\Verificar.ps1"
exit /b %ERRORLEVEL%
