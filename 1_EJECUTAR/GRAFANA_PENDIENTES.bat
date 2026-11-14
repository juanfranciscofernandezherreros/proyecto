@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\grafana_pendientes.py
python "%~dp0..\scripts\py\lanzadores\grafana_pendientes.py" %*
exit /b %ERRORLEVEL%
