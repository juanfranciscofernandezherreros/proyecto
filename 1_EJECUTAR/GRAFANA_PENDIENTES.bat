@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

rem Arranca lo necesario para ver los partidos pendientes en Grafana y abre el dashboard.
rem Reimporta el dashboard desde csv-extra-batch\observability\fixtures-pending-dashboard.json.
call "%SCRIPTS%\arranque\ASEGURAR.bat" antibloqueo postgres auditoria grafana --actualizar-dashboard
if errorlevel 1 exit /b %ERRORLEVEL%

if not defined GRAFANA_URL set "GRAFANA_URL=http://localhost:8084"
set "DASHBOARD=%GRAFANA_URL%/d/fixtures-audit-live"
echo Abriendo %DASHBOARD%
start "" "%DASHBOARD%"
exit /b 0
