@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\auditoria_fixtures.py
python "%~dp0..\scripts\py\lanzadores\auditoria_fixtures.py" %*
exit /b %ERRORLEVEL%
