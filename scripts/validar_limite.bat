@echo off
rem Uso interno: call validar_limite.bat "<valor>"  ->  exit 0 si es un entero >= 0.
setlocal EnableExtensions
set "VALUE=%~1"
if not defined VALUE goto invalid
for /f "delims=0123456789" %%C in ("%VALUE%") do goto invalid
exit /b 0

:invalid
echo [ERROR] El limite debe ser un numero entero: "%VALUE%"
exit /b 1
