@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\estado.py
python "%~dp0..\scripts\py\lanzadores\estado.py" %*
exit /b %ERRORLEVEL%
