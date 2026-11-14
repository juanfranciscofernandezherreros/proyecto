@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\vigilar_servicios.py
python "%~dp0..\scripts\py\lanzadores\vigilar_servicios.py" %*
exit /b %ERRORLEVEL%
