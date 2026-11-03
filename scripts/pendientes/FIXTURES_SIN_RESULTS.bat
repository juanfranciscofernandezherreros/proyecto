@echo off
setlocal EnableExtensions
call "%~dp0..\config.bat"

rem Muestra, por competicion, los partidos del calendario (fixtures) ya jugados que aun no
rem tienen resultado (results). Explicacion completa en
rem sql\consultas\2026-11-03_1300_fixtures-jugados-sin-results.sql
rem Uso: FIXTURES_SIN_RESULTS.bat   (solo lectura; requiere postgres arrancado)
docker compose -f "%COMPOSE_FILE%" exec -T postgres psql -U %DB_USER% -d %DB_NAME% < "%~dp0..\..\sql\consultas\2026-11-03_1300_fixtures-jugados-sin-results.sql"
if errorlevel 1 (
  echo Error: no se pudieron consultar los partidos sin resultado.
  exit /b 1
)
exit /b 0
