@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\verificar.py
python "%~dp0..\scripts\py\lanzadores\verificar.py" %*
exit /b %ERRORLEVEL%
