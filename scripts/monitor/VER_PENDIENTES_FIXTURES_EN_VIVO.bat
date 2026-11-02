@echo off
setlocal EnableExtensions
title Partidos pendientes en tiempo real
call "%~dp0..\config.bat"
call "%SCRIPTS%\arranque\ASEGURAR.bat" auditoria || exit /b 1
%PS% -File "%SCRIPTS%\monitor\VER_PENDIENTES_FIXTURES_EN_VIVO.ps1"
exit /b %ERRORLEVEL%
