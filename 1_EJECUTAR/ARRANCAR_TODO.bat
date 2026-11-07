@echo off
setlocal EnableExtensions
title Basketball - arrancar todo (web + procesamiento CSV)
rem =============================================================================
rem Arranca TODO lo descrito en docs\ESPECIFICACIONES.md / CLAUDE.md:
rem   1) La web y sus servicios (stack docker de local-validation).
rem   2) El procesamiento de CSV (csv-batch-launcher).
rem Luego verifica web (8083) y API (8082).
rem =============================================================================
call "%~dp0..\scripts\config.bat" || exit /b 1

echo.
echo === 1) Web y servicios (docker compose) ===
pushd "%WORKSPACE%\local-validation" || (echo ERROR: no existe %WORKSPACE%\local-validation & exit /b 1)
docker compose up -d --build mongo basketball-match-projector basketball-match-api basketball-match-web
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" (echo ERROR: fallo el docker compose ^(codigo %RC%^). & exit /b %RC%)

echo.
echo === 2) Procesamiento de CSV (launcher) ===
call "%SCRIPTS%\arranque\ASEGURAR.bat" launcher || exit /b 1

echo.
echo === Verificacion ===
curl -s -o NUL -w "  web 8083 -> %%{http_code}\n" http://localhost:8083/
curl -s -o NUL -w "  api 8082 -> %%{http_code}\n" http://localhost:8082/actuator/health
echo.
echo Web:      http://localhost:8083
echo API:      http://localhost:8082
echo Launcher: %LAUNCHER_URL%
echo Grafana:  %GRAFANA_URL%
echo.
echo Listo. La web tarda ~1 min en reflejar CSV nuevos (Postgres -^> projector -^> Mongo).
endlocal
exit /b 0
