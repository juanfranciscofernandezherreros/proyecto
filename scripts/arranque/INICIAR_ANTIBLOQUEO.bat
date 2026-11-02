@echo off
setlocal EnableExtensions

rem Mantiene el PC despierto con la API de Windows (SetThreadExecutionState), sin simular teclado.
set "ANTIBLOQUEO=%~dp0MANTENER_DESPIERTO.bat"
if not exist "%ANTIBLOQUEO%" (
    echo ERROR: No se encontro el antibloqueo en "%ANTIBLOQUEO%".
    exit /b 1
)

rem Mientras ejecuta un comando, cmd anade " - comando" al titulo de la ventana;
rem por eso el filtro termina en * (si no, se abririan ventanas duplicadas).
tasklist /v /fi "IMAGENAME eq cmd.exe" /fi "WINDOWTITLE eq Mantener PC Activo*" /fo csv /nh | findstr /i /c:"Mantener PC Activo" >nul
if not errorlevel 1 (
    echo Antibloqueo ya esta en ejecucion.
    exit /b 0
)

rem El antibloqueo vive indefinidamente y hereda los ficheros abiertos de quien lo lanza:
rem no llames a este .bat con la salida redirigida a un log que se vaya a seguir usando.
start "Antibloqueo" /min "%ComSpec%" /c call "%ANTIBLOQUEO%"
echo Antibloqueo iniciado.
exit /b 0
