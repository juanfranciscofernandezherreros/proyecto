@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

rem Comprueba, liga a liga, que el ultimo RESULTS y FIXTURES estan importados y que no hay
rem partidos jugados sin resultado, antes de seguir con los pendientes (MATCHIDS_PENDIENTES).
rem Al final: si a_revisar = 0, todo esta registrado. Explicacion completa en
rem sql\consultas\2026-11-03_1710_results-y-fixtures-listos-para-pendientes.sql
rem Uso: COMPROBAR_RESULTS_FIXTURES.bat   (solo lectura; requiere postgres arrancado)
docker compose -f "%COMPOSE_FILE%" exec -T postgres psql -U %DB_USER% -d %DB_NAME% < "%~dp0..\sql\consultas\2026-11-03_1710_results-y-fixtures-listos-para-pendientes.sql"
if errorlevel 1 (
  echo Error: no se pudo hacer la comprobacion.
  exit /b 1
)
exit /b 0
