@echo off
setlocal EnableExtensions
call "%~dp0..\scripts\config.bat"

rem Imprime los match_id de fixtures cuya fecha local (Europe/Madrid) fue ayer.
if not defined PG_USER set "PG_USER=test"
if not defined PG_DB set "PG_DB=basketball"
call "%SCRIPTS%\arranque\ASEGURAR.bat" postgres || exit /b 1

docker compose -f "%COMPOSE_FILE%" exec -T postgres psql -U %PG_USER% -d %PG_DB% -Atc "SELECT f.match_id FROM fixtures.fixtures f WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = ((now() AT TIME ZONE 'Europe/Madrid')::date - 1) ORDER BY f.match_id;"
if errorlevel 1 (
  echo.
  echo Error: no se pudieron consultar los partidos de ayer.
  exit /b 1
)
exit /b 0
