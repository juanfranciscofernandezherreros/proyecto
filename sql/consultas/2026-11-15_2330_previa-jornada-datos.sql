-- =============================================================================
-- DATOS DE LA PRÓXIMA JORNADA DE UNA LIGA, EN JSON (para `basket pronostico datos`)
-- =============================================================================
-- Fecha:     2026-11-15 23:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball -X -q -t -A -v pais=europe -v competicion=euroleague < sql\consultas\2026-11-15_2330_previa-jornada-datos.sql
--
-- PARA QUÉ SIRVE   Es la consulta que lanza `scripts\py\pronostico\previa.py`. Devuelve
--                  una sola fila con un JSON de tres claves: `fixtures` (partidos de la
--                  liga de los próximos 21 días que aún no tienen resultado), `equipos`
--                  (estado de forma de cada equipo con sus partidos ya jugados) y
--                  `resultados` (cuántos partidos con marcador hay). Es la versión para
--                  máquina de 2026-11-15_2245_pronostico-euroliga-proxima-jornada.sql.
-- CUÁNDO USARLA    No hace falta lanzarla a mano: la ejecuta `basket pronostico datos`.
--                  A mano sirve para ver qué datos recibe el script. `pais` y
--                  `competicion` son variables de psql (los slugs de fixtures.fixtures).
-- CÓMO LEER EL RESULTADO
--                  `fixtures[].inicio` va en UTC. En `equipos`, `dif_temp` y `dif_ult5`
--                  son el diferencial medio de puntos de toda la temporada y de los
--                  últimos cinco partidos; `casa` y `fuera` son balances "ganados-perdidos".
--                  Si `fixtures` sale vacío no hay calendario futuro cargado; si un equipo
--                  de `fixtures` no está en `equipos`, su nombre no cruza con results.
-- QUÉ HACER DESPUÉS
--                  El script corta la jornada (hasta que un equipo se repite) y calcula
--                  margen = 0,65·Δdif_temp + 0,35·Δdif_ult5 + 2,5 y
--                  probabilidad local = 1 / (1 + exp(−margen / 9)).
-- RESULTADO EL 2026-11-15 23:30   ver al final del fichero.
-- =============================================================================

-- PASO 1 · Un único JSON con el calendario próximo y la forma de cada equipo.
WITH lados AS (
    SELECT r.event_datetime, r.home_team AS equipo, true AS local,
           r.home_score AS pf, r.away_score AS pc
    FROM results.results r
    WHERE r.country = :'pais' AND r.competition = :'competicion'
      AND r.home_score IS NOT NULL AND r.away_score IS NOT NULL
    UNION ALL
    SELECT r.event_datetime, r.away_team, false, r.away_score, r.home_score
    FROM results.results r
    WHERE r.country = :'pais' AND r.competition = :'competicion'
      AND r.home_score IS NOT NULL AND r.away_score IS NOT NULL
), numerados AS (
    SELECT l.*, row_number() OVER (PARTITION BY equipo ORDER BY event_datetime DESC) AS orden
    FROM lados l
), forma AS (
    SELECT equipo,
           count(*)                                              AS pj,
           count(*) FILTER (WHERE pf > pc)                       AS g,
           count(*) FILTER (WHERE pf < pc)                       AS p,
           round(avg(pf), 1)                                     AS pf,
           round(avg(pc), 1)                                     AS pc,
           round(avg(pf - pc), 1)                                AS dif_temp,
           round(avg(pf - pc) FILTER (WHERE orden <= 5), 1)      AS dif_ult5,
           count(*) FILTER (WHERE orden <= 5 AND pf > pc)        AS g_ult5,
           count(*) FILTER (WHERE local AND pf > pc) || '-' ||
           count(*) FILTER (WHERE local AND pf < pc)             AS casa,
           count(*) FILTER (WHERE NOT local AND pf > pc) || '-' ||
           count(*) FILTER (WHERE NOT local AND pf < pc)         AS fuera
    FROM numerados
    GROUP BY equipo
), proximos AS (
    SELECT f.match_id,
           to_char(f.event_datetime AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inicio,
           f.home_team,
           f.away_team
    FROM fixtures.fixtures f
    WHERE f.country = :'pais' AND f.competition = :'competicion'
      AND f.event_datetime > now()
      AND f.event_datetime < now() + interval '21 days'
      AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id)
)
SELECT json_build_object(
    'fixtures',   (SELECT coalesce(json_agg(x ORDER BY x.inicio, x.home_team), '[]'::json) FROM proximos x),
    'equipos',    (SELECT coalesce(json_agg(e ORDER BY e.g DESC, e.dif_temp DESC), '[]'::json) FROM forma e),
    'resultados', (SELECT count(*) FROM results.results r
                   WHERE r.country = :'pais' AND r.competition = :'competicion'
                     AND r.home_score IS NOT NULL AND r.away_score IS NOT NULL)
);

-- RESULTADO EL 2026-11-15 23:30 (pais=europe, competicion=euroleague, vía `basket pronostico datos`)
--   Una fila con el JSON: 30 partidos en `fixtures` (los 10 primeros forman la jornada 12,
--   17 y 18 de noviembre), 20 equipos en `equipos` y `resultados` = 110.
