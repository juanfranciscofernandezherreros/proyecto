@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo watcher postgres auditoria
if errorlevel 1 exit /b %ERRORLEVEL%

start "Pendientes de fixtures en vivo" "%ComSpec%" /k call "%SCRIPTS%\monitor\VER_PENDIENTES_FIXTURES_EN_VIVO.bat"
echo Consola de pendientes abierta. Endpoint: %AUDIT_URL%/latest
exit /b 0
