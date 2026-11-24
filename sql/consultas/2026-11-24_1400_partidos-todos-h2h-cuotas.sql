-- =============================================================================
-- TODOS LOS PARTIDOS: CUÁNTOS TIENEN YA H2H Y CUOTAS Y CUÁLES FALTAN
-- =============================================================================
-- Fecha:     2026-11-24 14:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1400_partidos-todos-h2h-cuotas.sql
--
-- PARA QUÉ SIRVE   Petición «que se extraigan todos los H2H y cuotas de los partidos».
--                  Cuenta todos los partidos conocidos (fixtures y results) por
--                  competición y cuántos tienen ya filas en h2h.h2h y odds.odds, para
--                  dimensionar la extracción (unos 2 min por partido y navegador).
-- CUÁNDO USARLA    Antes y después de una extracción masiva de H2H y cuotas.
-- CÓMO LEER EL RESULTADO  Paso 1: por competición, partidos, con H2H, con cuotas y sin
--                  H2H. Paso 2: lista de match_id sin H2H (la que se pasa a reextraer
--                  con --fichero), del más reciente al más antiguo.
-- QUÉ HACER DESPUÉS       Repartir el Paso 2 en lotes y lanzar basket reextraer
--                  --dataset h2h-cuotas con --progreso.
-- RESULTADO EL 2026-11-24  3533 partidos; 233 con H2H y 276 con cuotas; 3300 sin H2H
--                  (NBA 1248, euroleague 291, liga-endesa 279, bbl 267...). Por tramo:
--                  794 jugados, 133 próximos 14 días, 2372 más adelante. Paso 2 (ya con
--                  algunos cargados): 3298, repartidos en 4 lotes lista-t1..t4.
-- =============================================================================

-- PASO 1 · Por competición: partidos, con H2H, con cuotas y pendientes.
WITH partidos AS (
    SELECT match_id, competition FROM fixtures.fixtures
    UNION
    SELECT match_id, competition FROM results.results
)
SELECT p.competition,
       count(DISTINCT p.match_id) AS partidos,
       count(DISTINCT h.match_id) AS con_h2h,
       count(DISTINCT o.match_id) AS con_cuotas,
       count(DISTINCT p.match_id) - count(DISTINCT h.match_id) AS sin_h2h
FROM partidos p
LEFT JOIN h2h.h2h h ON h.match_id = p.match_id
LEFT JOIN odds.odds o ON o.match_id = p.match_id
GROUP BY ROLLUP (p.competition)
ORDER BY p.competition NULLS LAST;

-- PASO 2 · match_id sin H2H, del más reciente al más antiguo.
SELECT match_id
FROM (
    SELECT match_id, event_datetime FROM fixtures.fixtures
    UNION ALL
    SELECT match_id, event_datetime FROM results.results
) p
WHERE NOT EXISTS (SELECT 1 FROM h2h.h2h h WHERE h.match_id = p.match_id)
GROUP BY match_id
ORDER BY max(event_datetime) DESC NULLS LAST;

-- PASO 3 · Pendientes (sin H2H) por tramo temporal: jugados, próximos 14 días y más
--          adelante, para decidir el orden y el alcance de la extracción.
SELECT CASE WHEN event_datetime < now() THEN '1 jugados'
            WHEN event_datetime < now() + interval '14 days' THEN '2 proximos 14 dias'
            ELSE '3 mas adelante' END AS tramo,
       count(*) AS partidos
FROM (
    SELECT match_id, max(event_datetime) AS event_datetime
    FROM (SELECT match_id, event_datetime FROM fixtures.fixtures
          UNION ALL SELECT match_id, event_datetime FROM results.results) u
    WHERE NOT EXISTS (SELECT 1 FROM h2h.h2h h WHERE h.match_id = u.match_id)
    GROUP BY match_id
) p
GROUP BY 1 ORDER BY 1;
