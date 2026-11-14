@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\automatico_inicio.py
python "%~dp0..\scripts\py\lanzadores\automatico_inicio.py" %*
exit /b %ERRORLEVEL%
