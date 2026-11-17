-- =============================================================================
-- PARTIDOS JUGADOS DE UNA LIGA CON SUS PARCIALES, EN JSON (análisis ampliado de la previa)
-- =============================================================================
-- Fecha:     2026-11-15 23:45
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball -X -q -t -A -v pais=europe -v competicion=euroleague < sql\consultas\2026-11-15_2345_previa-jornada-partidos.sql
--
-- PARA QUÉ SIRVE   Segunda consulta de `basket pronostico datos`. La primera
--                  (2026-11-15_2330_previa-jornada-datos.sql) da las medias con las que
--                  se calcula el pronóstico; esta devuelve los partidos uno a uno, con el
--                  marcador y los parciales de cada cuarto, para el análisis ampliado que
--                  hace `scripts\py\pronostico\previa.py`: rendimiento en casa y fuera,
--                  diferencial por cuartos, partidos ajustados, dureza del calendario,
--                  días de descanso, enfrentamientos directos y contraste del modelo
--                  contra los partidos ya jugados.
-- CUÁNDO USARLA    No hace falta lanzarla a mano. Sirve para revisar qué partidos entran
--                  en el análisis de una liga (`pais` y `competicion` son variables de psql).
-- CÓMO LEER EL RESULTADO
--                  Una sola fila con un JSON: lista de partidos ordenada por fecha.
--                  `inicio` va en UTC. `home_periods` y `away_periods` son los puntos de
--                  cada periodo (el quinto es la prórroga; null si no la hubo o si el
--                  parcial no se cargó). Un partido sin `inicio` no puede ordenarse y el
--                  script lo descarta.
-- QUÉ HACER DESPUÉS
--                  Si faltan partidos recientes, cargar resultados (skill
--                  `resultados-todas-las-ligas`) antes de pronosticar.
-- RESULTADO EL 2026-11-15 23:45   ver al final del fichero.
-- =============================================================================

-- PASO 1 · Todos los partidos con marcador de la liga, con sus parciales.
SELECT coalesce(json_agg(p ORDER BY p.inicio, p.match_id), '[]'::json)
FROM (
    SELECT r.match_id,
           to_char(r.event_datetime AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inicio,
           r.home_team,
           r.away_team,
           r.home_score,
           r.away_score,
           json_build_array(r.home_score1, r.home_score2, r.home_score3, r.home_score4, r.home_score5) AS home_periods,
           json_build_array(r.away_score1, r.away_score2, r.away_score3, r.away_score4, r.away_score5) AS away_periods
    FROM results.results r
    WHERE r.country = :'pais' AND r.competition = :'competicion'
      AND r.home_score IS NOT NULL AND r.away_score IS NOT NULL
) p;
