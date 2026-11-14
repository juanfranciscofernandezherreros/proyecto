-- =============================================================================
-- EUROLIGA: HASTA DÓNDE LLEGAN LOS RESULTADOS Y QUÉ PARTIDOS FALTAN
-- =============================================================================
-- Fecha:     2026-11-14 13:55
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-14_1355_euroliga-resultados-pendientes.sql
--
-- PARA QUÉ SIRVE   Saber si hay que lanzar el scraper de resultados de la Euroliga.
--                  results.results guarda los marcadores ya extraídos y
--                  fixtures.fixtures el calendario completo. Un partido de fixtures
--                  con fecha pasada y posterior al último resultado cargado es un
--                  partido jugado cuyo marcador aún no se ha extraído.
-- CUÁNDO USARLA    Antes y después de 1_EJECUTAR\EXTRAER_RESULTADOS.bat EUROLIGA
--                  (skill extraer-euroliga): antes para ver qué falta, después para
--                  comprobar que ha entrado.
-- CÓMO LEER EL RESULTADO
--                  PASO 1: "ultimo" = fecha del último partido con resultado;
--                          "total" = partidos de Euroliga cargados.
--                  PASO 2: cada fila es un partido jugado sin marcador. Cero filas
--                          = results está al día.
--                  PASO 3: los últimos resultados cargados, del más reciente al más
--                          antiguo.
-- QUÉ HACER DESPUÉS
--                  Si el PASO 2 devuelve filas, lanzar la extracción y repetir esta
--                  consulta: "total" debe subir y el PASO 2 quedar vacío.
-- RESULTADO EL 2026-11-14
--                  Antes de extraer: ultimo = 2026-11-11 19:45+00, total = 102 y
--                  8 partidos pendientes (12 y 13 de noviembre).
--                  Después de extraer: ultimo = 2026-11-13 19:30+00, total = 110.
-- =============================================================================

-- PASO 1 · Último resultado cargado y total de partidos de Euroliga en results.
SELECT max(event_datetime) AS ultimo, count(*) AS total
FROM results.results
WHERE competition ILIKE 'euroleague';

-- PASO 2 · Partidos del calendario ya jugados y posteriores al último resultado
--          cargado: son los que tiene que traer el scraper.
SELECT f.event_datetime, f.home_team, f.away_team
FROM fixtures.fixtures f
WHERE f.competition ILIKE 'euroleague'
  AND f.event_datetime < now()
  AND f.event_datetime > (SELECT max(event_datetime)
                          FROM results.results
                          WHERE competition ILIKE 'euroleague')
ORDER BY f.event_datetime;

-- PASO 3 · Últimos resultados cargados, para enseñarlos tras la extracción.
SELECT event_datetime, home_team, home_score, away_score, away_team
FROM results.results
WHERE competition ILIKE 'euroleague'
ORDER BY event_datetime DESC NULLS LAST
LIMIT 15;
