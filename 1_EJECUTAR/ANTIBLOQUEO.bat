@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

rem Mantiene el PC despierto y la pantalla encendida (sin que se bloquee) mientras procesa.
rem Abre minimizada la ventana "Mantener PC Activo"; si ya esta abierta no abre otra.
rem Para detenerlo, cierra esa ventana.
call "%SCRIPTS%\arranque\INICIAR_ANTIBLOQUEO.bat"
exit /b %ERRORLEVEL%
