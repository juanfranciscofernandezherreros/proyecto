@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\comprobar_results_fixtures.py
python "%~dp0..\scripts\py\lanzadores\comprobar_results_fixtures.py" %*
exit /b %ERRORLEVEL%
