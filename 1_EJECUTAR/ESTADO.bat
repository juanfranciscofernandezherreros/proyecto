@echo off
setlocal EnableExtensions
title Basketball - estado del sistema
rem Estado del sistema en una sola pantalla (solo lectura): contenedores, servicios,
rem ultimas cargas del launcher, resultados por liga y partidos pendientes.
rem No arranca ni modifica nada. Codigo de salida 0 = todo responde, 1 = falta algo.
rem Uso: ESTADO.bat
call "%~dp0..\scripts\config.bat" || exit /b 1
%PS% -File "%SCRIPTS%\Estado.ps1"
exit /b %ERRORLEVEL%
