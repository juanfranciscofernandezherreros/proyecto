@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\datos_euroliga.py
python "%~dp0..\scripts\py\lanzadores\datos_euroliga.py" %*
exit /b %ERRORLEVEL%
