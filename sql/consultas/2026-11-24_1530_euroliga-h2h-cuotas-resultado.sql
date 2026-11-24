-- =============================================================================
-- EUROLIGA ÚLTIMAS DOS SEMANAS: PARTIDOS CON H2H Y CUOTAS TRAS LA EXTRACCIÓN
-- =============================================================================
-- Fecha:     2026-11-24 15:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1530_euroliga-h2h-cuotas-resultado.sql
--
-- PARA QUÉ SIRVE   Cierre de la extracción de H2H y cuotas de los partidos de Euroliga
--                  jugados en los últimos 14 días (lotes lista-e1/e2). Cuenta cuántos
--                  partidos tienen filas en h2h.h2h y odds.odds y lista los que no.
-- CUÁNDO USARLA    Tras una extracción de H2H y cuotas de Euroliga.
-- CÓMO LEER EL RESULTADO  Paso 1: partidos, con H2H y con cuotas (lo bueno: los tres
--                  iguales). Paso 2: los que falten, con su fecha.
-- QUÉ HACER DESPUÉS       Si falta alguno, basket reextraer --dataset h2h-cuotas <id>.
-- RESULTADO EL 2026-11-24  Paso 1: 30 partidos, 30 con H2H, 30 con cuotas. Paso 2:
--                  0 filas. En Mongo también 30/30/30 (el último, thIAMoUj, proyectado
--                  a las 11:31:05 UTC). Paso 3 (tras los lotes P1/P2, 25 + 25 CSV OK, 0
--                  fallos): los 10 próximos con H2H (12–15 filas) y cuotas (132–224 filas).
-- =============================================================================

-- PASO 1 · Totales.
WITH p AS (
    SELECT DISTINCT match_id FROM results.results
    WHERE competition = 'euroleague'
      AND event_datetime >= now() - interval '14 days' AND event_datetime < now()
)
SELECT count(*) AS partidos,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM h2h.h2h h WHERE h.match_id = p.match_id)) AS con_h2h,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM odds.odds o WHERE o.match_id = p.match_id)) AS con_cuotas
FROM p;

-- PASO 2 · Partidos sin H2H o sin cuotas.
SELECT r.match_id, r.event_datetime, r.home_team, r.away_team
FROM results.results r
WHERE r.competition = 'euroleague'
  AND r.event_datetime >= now() - interval '14 days' AND r.event_datetime < now()
  AND (NOT EXISTS (SELECT 1 FROM h2h.h2h h WHERE h.match_id = r.match_id)
       OR NOT EXISTS (SELECT 1 FROM odds.odds o WHERE o.match_id = r.match_id))
ORDER BY r.event_datetime DESC;

-- PASO 3 · «Actualiza la información»: partidos de Euroliga de los próximos 7 días (sin
--          resultado), con o sin H2H, para volver a extraer H2H y cuotas (las cuotas
--          cambian hasta el inicio del partido). Del más cercano al más lejano.
SELECT f.match_id, f.event_datetime, f.home_team, f.away_team,
       (SELECT count(*) FROM h2h.h2h h WHERE h.match_id = f.match_id) AS filas_h2h,
       (SELECT count(*) FROM odds.odds o WHERE o.match_id = f.match_id) AS filas_cuotas
FROM fixtures.fixtures f
WHERE f.competition = 'euroleague'
  AND f.event_datetime >= now() AND f.event_datetime < now() + interval '7 days'
  AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id AND r.home_score IS NOT NULL)
ORDER BY f.event_datetime;
