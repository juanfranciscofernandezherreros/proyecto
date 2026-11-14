@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\ligas_orquestar.py
python "%~dp0..\scripts\py\lanzadores\ligas_orquestar.py" %*
exit /b %ERRORLEVEL%
