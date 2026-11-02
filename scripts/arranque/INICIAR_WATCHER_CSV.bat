@echo off
setlocal EnableExtensions

set "WATCHER=%~dp0..\monitor\watch_csv_imports.bat"
if not exist "%WATCHER%" (
    echo ERROR: No se encontro "%WATCHER%".
    exit /b 1
)

rem watch_csv_imports.bat fija este titulo; el * cubre el sufijo " - comando" de cmd.
tasklist /v /fi "IMAGENAME eq cmd.exe" /fi "WINDOWTITLE eq Basketball launcher import watcher*" /fo csv /nh | findstr /i /c:"Basketball launcher import watcher" >nul
if not errorlevel 1 (
    echo Monitor de CSV ya esta en ejecucion.
    exit /b 0
)

rem Igual que el antibloqueo: no lo llames con la salida redirigida a un log que se siga usando.
start "Monitor CSV" "%ComSpec%" /k call "%WATCHER%"
echo Monitor de CSV iniciado.
exit /b 0
