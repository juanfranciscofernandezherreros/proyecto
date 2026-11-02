@echo off
setlocal EnableExtensions
title Basketball launcher import watcher
call "%~dp0..\config.bat"

if not exist "%SCRIPTS%\monitor\watch_csv_processing.ps1" (
  echo ERROR: No se encuentra "%SCRIPTS%\monitor\watch_csv_processing.ps1".
  exit /b 1
)

rem El monitor consulta PostgreSQL con docker exec.
call "%SCRIPTS%\arranque\ASEGURAR.bat" postgres || exit /b 1
%PS% -File "%SCRIPTS%\monitor\watch_csv_processing.ps1"
exit /b %ERRORLEVEL%
