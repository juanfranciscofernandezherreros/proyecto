@echo off
rem Shim: delega en el lanzador Python scripts\py\lanzadores\arrancar_todo.py
python "%~dp0..\scripts\py\lanzadores\arrancar_todo.py" %*
exit /b %ERRORLEVEL%
