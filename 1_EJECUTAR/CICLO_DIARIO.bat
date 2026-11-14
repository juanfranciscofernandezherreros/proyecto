@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\ciclo_diario.py
python "%~dp0..\scripts\py\lanzadores\ciclo_diario.py" %*
exit /b %ERRORLEVEL%
