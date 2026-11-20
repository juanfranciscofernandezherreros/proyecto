-- =============================================================================
-- PARTIDOS GANADOS TRAS UNA GRAN REMONTADA
-- =============================================================================
-- Fecha:     2026-11-20 10:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-20_1000_partidos-ganados-tras-gran-remontada.sql
--
-- PARA QUÉ SIRVE   Encontrar los partidos en los que el ganador llegó a ir perdiendo
--                  por mucho. Cruza el jugada a jugada (point_by_point.point_by_point_event,
--                  marcador tras cada canasta) con el resultado final (results.results).
--                  El ganador sale de results porque el jugada a jugada solo trae los
--                  cuatro cuartos (no las prórrogas).
-- CUÁNDO USARLA    Para curiosidades/artículos o tras cargar jugadas nuevas.
-- CÓMO LEER EL RESULTADO
--   desventaja_max   puntos que llegó a perder el ganador (cuanto más, mayor remontada)
--   cuando           cuarto y marcador (local-visitante) en el peor momento del ganador
--   final            marcador final de results; "prorroga" = sí si hubo quinto periodo
--   Umbral: "gran remontada" = desventaja de 15 puntos o más.
-- QUÉ HACER DESPUÉS  Si un partido sale raro, revisarlo con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-20  59 partidos (de 888 con jugada a jugada). Mayor remontada:
--                  Philadelphia 76ers - Cleveland Cavaliers (vqjr83tS), 40-69 en el 2º
--                  cuarto y final 114-106 (29 puntos). Le siguen Oldenburg - Hamburg (26)
--                  y Golden State - Lakers (25).
-- =============================================================================

-- PASO 1 · Para cada partido terminado con jugada a jugada, desventaja máxima del ganador
--          y el momento en que se produjo; se listan las de 15 puntos o más.
WITH ganador AS (
    SELECT r.match_id, r.home_team, r.away_team, r.home_score, r.away_score,
           r.competition, r.event_datetime,
           (r.home_score5 IS NOT NULL OR r.away_score5 IS NOT NULL) AS prorroga,
           CASE WHEN r.home_score > r.away_score THEN 'home' ELSE 'away' END AS lado
    FROM results.results r
    WHERE r.home_score IS NOT NULL AND r.away_score IS NOT NULL
      AND r.home_score <> r.away_score
),
desventaja AS (
    SELECT g.match_id, p.quarter, p.sequence, p.home_score, p.away_score,
           CASE WHEN g.lado = 'home' THEN p.away_score - p.home_score
                ELSE p.home_score - p.away_score END AS deficit
    FROM ganador g
    JOIN point_by_point.point_by_point_event p ON p.match_id = g.match_id
),
peor_momento AS (
    SELECT DISTINCT ON (match_id) match_id, quarter, home_score, away_score, deficit
    FROM desventaja
    ORDER BY match_id, deficit DESC, quarter, sequence
)
SELECT g.event_datetime::date AS fecha,
       g.competition,
       g.home_team || ' - ' || g.away_team AS partido,
       CASE WHEN g.lado = 'home' THEN g.home_team ELSE g.away_team END AS ganador,
       pm.deficit AS desventaja_max,
       pm.quarter || ' ' || pm.home_score || '-' || pm.away_score AS cuando,
       g.home_score || '-' || g.away_score AS final,
       CASE WHEN g.prorroga THEN 'sí' ELSE '' END AS prorroga,
       g.match_id
FROM peor_momento pm
JOIN ganador g USING (match_id)
WHERE pm.deficit >= 15
ORDER BY pm.deficit DESC, g.event_datetime DESC;
