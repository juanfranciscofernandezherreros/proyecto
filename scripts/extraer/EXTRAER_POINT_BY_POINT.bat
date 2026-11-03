@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Extraer POINT_BY_POINT siguiendo redireccion de Flashscore
call "%~dp0..\config.bat"

rem Uso: EXTRAER_POINT_BY_POINT.bat [pais] [competicion] [limite]
rem Toma las primeras [limite] filas del RESULTS mas reciente de la competicion.
set "COUNTRY=%~1"
set "COMPETITION=%~2"
set "LIMIT=%~3"
if not defined COUNTRY set "COUNTRY=europe"
if not defined COMPETITION set "COMPETITION=euroleague"
if not defined LIMIT set "LIMIT=20"
call "%~dp0..\validar_limite.bat" "%LIMIT%" || exit /b 1

set "RESOLVER=%WORKSPACE%\python\resolve_flashscore_redirect.py"
set "RESULTS_DIR=%COMPETITIONS_DIR%\%COUNTRY%\%COMPETITION%"

if not exist "%PYTHON%" echo [ERROR] No se encuentra Python: %PYTHON% & exit /b 1
if not exist "%SCRAPER%" echo [ERROR] No se encuentra el scraper: %SCRAPER% & exit /b 1
if not exist "%RESOLVER%" echo [ERROR] No se encuentra el resolvedor: %RESOLVER% & exit /b 1
if not exist "%RESULTS_DIR%" echo [ERROR] No existe la carpeta: %RESULTS_DIR% & exit /b 1

set "RESULTS_CSV="
for /f "delims=" %%F in ('dir /b /a-d /o-d "%RESULTS_DIR%\RESULTS_*_%COUNTRY%_%COMPETITION%.csv" 2^>nul') do if not defined RESULTS_CSV set "RESULTS_CSV=%RESULTS_DIR%\%%F"
if not defined RESULTS_CSV echo [ERROR] No hay RESULTS para %COUNTRY%/%COMPETITION%. & exit /b 1

echo RESULTS seleccionado: %RESULTS_CSV%
echo Flujo: ID ^> Point by Point ^> cuartos. Limite: %LIMIT%
rem Los partidos que ya tienen POINT_BY_POINT en PostgreSQL se saltan y no cuentan para el limite.
set "IMPORTED_IDS=%TEMP%\pbp-importados-%RANDOM%%RANDOM%.txt"
%PS% -File "%~dp0PARTIDOS_YA_IMPORTADOS.ps1" -Dataset POINT_BY_POINT -Salida "%IMPORTED_IDS%"
if errorlevel 1 echo [ERROR] No se pudieron leer los partidos ya importados. & exit /b 1
set /a COUNT=0
set "FAILED=0"
for /f "usebackq skip=1 tokens=1 delims=," %%M in ("%RESULTS_CSV%") do (
    set "MATCH_ID=%%~M"
    if defined MATCH_ID findstr /x /c:"%%~M" "%IMPORTED_IDS%" >nul 2>&1 && (
        echo [%%~M] ya importado; se salta.
        set "MATCH_ID="
    )
    if !COUNT! LSS %LIMIT% (
        if defined MATCH_ID (
            set /a COUNT+=1
            set "MATCH_URL="
            for /f "delims=" %%U in ('""%PYTHON%" "%RESOLVER%" !MATCH_ID! 2^>nul"') do set "MATCH_URL=%%U"
            if not defined MATCH_URL (
                echo [ERROR] [!MATCH_ID!] Flashscore no devolvio la URL canonica.
                set "FAILED=1"
            ) else (
                echo.
                echo [!COUNT!/%LIMIT%] ID: !MATCH_ID!
                echo Redirigido a: !MATCH_URL!
                set "PBP_OK="
                for /L %%A in (1,1,3) do if not defined PBP_OK (
                    echo [!MATCH_ID!] POINT_BY_POINT intento %%A/3
                    "%PYTHON%" "%SCRAPER%" match quarters "!MATCH_URL!" --mid !MATCH_ID! --output "%RESULTS_DIR%\POINT_BY_POINT_!MATCH_ID!.csv"
                    if errorlevel 1 (
                        echo [WARN] [!MATCH_ID!] Extraccion POINT_BY_POINT fallida; se reintentara.
                    ) else (
                        for /f %%D in ('powershell.exe -NoProfile -Command "$f=Get-ChildItem -LiteralPath '%RESULTS_DIR%' -File -Filter 'POINT_BY_POINT_*_!MATCH_ID!.csv' ^| Sort-Object LastWriteTime -Descending ^| Select-Object -First 1; if ($f -and (Get-Content -LiteralPath $f.FullName ^| Select-Object -Skip 1 -First 1)) { 'DATA' }"') do set "PBP_OK=%%D"
                        if not defined PBP_OK echo [WARN] [!MATCH_ID!] CSV vacio; se reintentara.
                    )
                )
                rem Solo cuenta como fallo si tras los 3 intentos no hay datos.
                if not defined PBP_OK (
                    echo [ERROR] [!MATCH_ID!] Sin POINT_BY_POINT tras 3 intentos.
                    set "FAILED=1"
                )
            )
        )
    )
)
del "%IMPORTED_IDS%" >nul 2>&1
if !COUNT! EQU 0 echo Todos los partidos del RESULTS ya tienen POINT_BY_POINT. No se extrae nada. & exit /b 0
if "!FAILED!"=="1" exit /b 1
echo.
echo OK. POINT_BY_POINT generado junto a RESULTS en: %RESULTS_DIR%
exit /b 0
