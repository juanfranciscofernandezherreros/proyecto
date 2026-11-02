@echo off
rem Configuracion comun de todos los .bat. Se carga con:
rem     call "%~dp0..\config.bat"   (desde scripts\<capa>\)
rem     call "%~dp0..\scripts\config.bat"   (desde 1_EJECUTAR\)
rem Los valores salen de config\basketball.env (y config\basketball.local.env); los calcula
rem config.ps1, el mismo lector que usan los .ps1, para que todos vean lo mismo.
rem No usa setlocal para que las variables lleguen al script que la llama.

for /f "usebackq tokens=1* delims==" %%A in (`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0config.ps1" -FormatoBat`) do set "%%A=%%B"
if not defined WORKSPACE (
    echo ERROR: no se pudo leer la configuracion de config\basketball.env.
    exit /b 1
)

set "PS=powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass"
exit /b 0
