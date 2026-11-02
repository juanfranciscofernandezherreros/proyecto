@echo off
rem Configuracion comun de todos los .bat. Se carga con:
rem     call "%~dp0..\config.bat"   (desde scripts\<capa>\)
rem     call "%~dp0..\scripts\config.bat"   (desde 1_EJECUTAR\)
rem No usa setlocal para que las variables lleguen al script que la llama.
rem Cualquier variable ya definida en el entorno tiene prioridad.

for %%I in ("%~dp0..") do set "WORKSPACE=%%~fI"
set "SCRIPTS=%WORKSPACE%\scripts"

if not defined DATA_DIR set "DATA_DIR=C:\data\basketball"
if not defined COMPETITIONS_DIR set "COMPETITIONS_DIR=%DATA_DIR%\competitions"
if not defined REPORT_DIR set "REPORT_DIR=%DATA_DIR%\reports\orchestrator"

if not defined JAVA_EXE set "JAVA_EXE=C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe"
if not defined PYTHON set "PYTHON=%WORKSPACE%\python-pyppeter\.venv\Scripts\python.exe"
if not defined SCRAPER set "SCRAPER=%WORKSPACE%\python-pyppeter\flashscore.py"

if not defined DOCKER_DESKTOP set "DOCKER_DESKTOP=C:\Program Files\Docker\Docker\Docker Desktop.exe"
if not defined COMPOSE_FILE set "COMPOSE_FILE=%WORKSPACE%\local-validation\docker-compose.yml"

if not defined AUDIT_URL set "AUDIT_URL=http://localhost:8090/fixtures-processing-audit"
if not defined LAUNCHER_URL set "LAUNCHER_URL=http://localhost:8088/"

set "PS=powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass"
exit /b 0
