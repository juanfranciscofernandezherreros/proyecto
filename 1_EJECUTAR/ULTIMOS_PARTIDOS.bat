@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\ultimos_partidos.py
python "%~dp0..\scripts\py\lanzadores\ultimos_partidos.py" %*
exit /b %ERRORLEVEL%
