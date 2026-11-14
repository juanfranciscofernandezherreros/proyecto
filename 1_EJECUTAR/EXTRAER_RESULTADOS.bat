@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\extraer_resultados.py
python "%~dp0..\scripts\py\lanzadores\extraer_resultados.py" %*
exit /b %ERRORLEVEL%
