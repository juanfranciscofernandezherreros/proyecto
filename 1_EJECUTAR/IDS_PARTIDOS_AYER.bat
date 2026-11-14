@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\ids_partidos_ayer.py
python "%~dp0..\scripts\py\lanzadores\ids_partidos_ayer.py" %*
exit /b %ERRORLEVEL%
