@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\procesar_csv_resultados.py
python "%~dp0..\scripts\py\lanzadores\procesar_csv_resultados.py" %*
exit /b %ERRORLEVEL%
