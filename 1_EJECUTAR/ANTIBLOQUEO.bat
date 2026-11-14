@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\antibloqueo.py
python "%~dp0..\scripts\py\lanzadores\antibloqueo.py" %*
exit /b %ERRORLEVEL%
