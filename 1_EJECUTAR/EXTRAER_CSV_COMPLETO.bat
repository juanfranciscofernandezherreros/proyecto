@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\extraer_csv_completo.py
python "%~dp0..\scripts\py\lanzadores\extraer_csv_completo.py" %*
exit /b %ERRORLEVEL%
