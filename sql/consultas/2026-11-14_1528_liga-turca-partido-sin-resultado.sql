-- =============================================================================
-- LIGA TURCA: QUÉ PARTIDO JUGADO SIGUE SIN RESULTADO Y POR QUÉ
-- =============================================================================
-- Fecha:     2026-11-14 15:28
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-14_1528_liga-turca-partido-sin-resultado.sql
--
-- PARA QUÉ SIRVE   1_EJECUTAR\basket.cmd estado marca una liga como "atrasada" cuando
--                  fixtures.fixtures tiene partidos con hora ya pasada y
--                  posteriores al último resultado de results.results. Esta
--                  consulta dice qué partido es y permite distinguir un fallo de
--                  extracción de un partido que simplemente está en juego.
-- CUÁNDO USARLA    Cuando ESTADO.bat siga mostrando "jugados sin resultado" en una
--                  liga justo después de extraer sus resultados. Para otra liga,
--                  cambiar country y competition en los pasos 2 y 3.
-- CÓMO LEER EL RESULTADO
--                  PASO 1: la hora actual de la base de datos, en UTC.
--                  PASO 2: calendario de los últimos 3 días y el día siguiente;
--                          en_results = 1 si el partido ya tiene marcador.
--                  PASO 3: los últimos resultados cargados de la liga.
--                  Un partido con en_results = 0 que empezó hace menos de unas
--                  2 h 30 min está en juego o recién terminado: no es un fallo.
--                  Si empezó hace más y sigue a 0 tras extraer, sí hay que mirarlo.
-- QUÉ HACER DESPUÉS
--                  En juego: esperar y repetir la extracción de esa liga (skill
--                  extraer-resultados). Fallo real: skill diagnosticar-partido.
-- RESULTADO EL 2026-11-14
--                  Ahora = 14:28 UTC. Único partido pasado sin resultado:
--                  tzc9nu9t Tofas - Trabzonspor, inicio 12:30 UTC. La extracción
--                  de la liga se hizo sobre las 14:20 UTC, a 1 h 50 min del
--                  inicio: el partido estaba en juego. No es un fallo. Quedan
--                  además dos partidos de hoy por empezar (15:00 y 17:30 UTC).
-- =============================================================================

-- PASO 1 · Hora actual de la base de datos, para comparar con el inicio de cada partido.
SELECT now() AS ahora;

-- PASO 2 · Calendario reciente de la liga turca y si cada partido tiene ya marcador.
SELECT f.match_id, f.event_datetime, f.home_team, f.away_team,
       (SELECT count(*) FROM results.results r WHERE r.match_id = f.match_id) AS en_results
FROM fixtures.fixtures f
WHERE f.country = 'turkey' AND f.competition = 'super-lig'
  AND f.event_datetime BETWEEN now() - interval '3 days' AND now() + interval '1 day'
ORDER BY f.event_datetime;

-- PASO 3 · Últimos resultados cargados de la liga turca.
SELECT match_id, event_datetime, home_team, home_score, away_score, away_team
FROM results.results
WHERE country = 'turkey' AND competition = 'super-lig'
ORDER BY event_datetime DESC NULLS LAST
LIMIT 4;
