-- =============================================================================
-- CURIOSIDADES DE CONTEXTO: COMPARATIVA DE LIGAS Y LA JORNADA EN NÚMEROS
-- =============================================================================
-- Fecha:     2026-11-23 14:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-23_1430_curiosidades-por-liga.sql
--            Filtros opcionales (psql): -v desde=2026-11-17 -v hasta=2026-11-23 (fechas de
--            Madrid; afectan a los dos pasos). Sin -v, toda la temporada cargada.
--
-- PARA QUÉ SIRVE   Bloques del vídeo que no son de un partido concreto (complementa a
--                  2026-11-23_1400_curiosidades-ampliadas.sql): qué liga anota más, cuántos
--                  triples y tiros libres se meten, el factor cancha y cuántos partidos se
--                  deciden por 5 o menos; y, día a día, «la jornada en números».
--                  Fuentes: results.results y stats_player.stats_player (sumas por partido).
--                  Sin la pretemporada de la NBA (mismo corte que la API).
-- CUÁNDO USARLA    Al preparar un vídeo o artículo semanal.
-- CÓMO LEER EL RESULTADO
--   PASO 1 (una fila por liga, de la que más anota a la que menos)
--     partidos, puntos_partido (de los dos equipos), triples_partido y libres_partido
--     (metidos entre los dos, solo partidos con estadísticas), pct_local (victorias del
--     local), pct_ajustados (decididos por 5 o menos), pct_prorroga.
--     La NBA juega cuartos de 12 minutos y el resto de 10: comparar la NBA aparte.
--   PASO 2 (un día por fila, del más reciente al más antiguo)
--     partidos y ligas del día, puntos totales, el partido con más puntos, la mayor
--     diferencia, el máximo anotador y cuántos se decidieron por 5 o menos.
-- QUÉ HACER DESPUÉS  Las curiosidades de cada partido salen de la consulta 1400.
-- RESULTADO EL 2026-11-23  PASO 1: 11 ligas. Más anotadora: NBA 226,7 por partido (aparte);
--                  de 10 minutos, Liga Endesa 185,0 y Basket League la que menos (159,6).
--                  Factor cancha: Liga Endesa 65,4 % y Süper Lig 65,3 % frente a NBA 52,0 %.
--                  Finales por 5 o menos: Euroliga 35,4 %, Süper Lig 34,7 %, BBL 18,2 %.
--                  Prórrogas: LNB 10,8 %. PASO 2: 77 días; el 15/11, 40 partidos de 9 ligas.
--                  El máximo anotador del día solo cuenta partidos con estadísticas cargadas
--                  (los pendientes aún no las tienen).
-- =============================================================================

-- PASO 0 · Valores por defecto de los filtros.
\if :{?desde}
\else
\set desde '1900-01-01'
\endif
\if :{?hasta}
\else
\set hasta '2999-12-31'
\endif

-- PASO 1 · Comparativa de ligas.
WITH r AS (
    SELECT r.*, (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date AS fecha
    FROM results.results r
    WHERE r.home_score IS NOT NULL AND r.away_score IS NOT NULL AND r.event_datetime IS NOT NULL
      AND NOT (r.competition = 'nba' AND r.event_datetime < TIMESTAMPTZ '2026-10-19 22:00:00+00')
),
f AS (
    SELECT * FROM r WHERE fecha BETWEEN :'desde'::date AND :'hasta'::date
),
st AS (
    SELECT match_id, SUM(COALESCE(threepm, 0)) AS triples, SUM(COALESCE(ftm, 0)) AS libres
    FROM stats_player.stats_player
    WHERE match_id IN (SELECT match_id FROM f)
    GROUP BY match_id
)
SELECT f.competition AS liga,
       COUNT(*) AS partidos,
       ROUND(AVG(f.home_score + f.away_score), 1) AS puntos_partido,
       ROUND(AVG(st.triples), 1) AS triples_partido,
       ROUND(AVG(st.libres), 1) AS libres_partido,
       ROUND(100.0 * AVG((f.home_score > f.away_score)::int), 1) AS pct_local,
       ROUND(100.0 * AVG((ABS(f.home_score - f.away_score) <= 5)::int), 1) AS pct_ajustados,
       ROUND(100.0 * AVG((f.home_score5 IS NOT NULL OR f.away_score5 IS NOT NULL)::int), 1) AS pct_prorroga
FROM f
LEFT JOIN st USING (match_id)
GROUP BY f.competition
ORDER BY puntos_partido DESC;

-- PASO 2 · La jornada en números, día a día (del más reciente al más antiguo).
WITH r AS (
    SELECT r.*, (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date AS fecha
    FROM results.results r
    WHERE r.home_score IS NOT NULL AND r.away_score IS NOT NULL AND r.event_datetime IS NOT NULL
      AND NOT (r.competition = 'nba' AND r.event_datetime < TIMESTAMPTZ '2026-10-19 22:00:00+00')
),
f AS (
    SELECT * FROM r WHERE fecha BETWEEN :'desde'::date AND :'hasta'::date
),
mas_puntos AS (
    SELECT DISTINCT ON (fecha) fecha,
           home_team || ' ' || home_score || '-' || away_score || ' ' || away_team
           || ' (' || competition || ')' AS partido
    FROM f ORDER BY fecha, home_score + away_score DESC
),
mayor_dif AS (
    SELECT DISTINCT ON (fecha) fecha,
           home_team || ' ' || home_score || '-' || away_score || ' ' || away_team
           || ' (' || competition || ')' AS partido
    FROM f ORDER BY fecha, ABS(home_score - away_score) DESC
),
anotador AS (
    SELECT DISTINCT ON (f.fecha) f.fecha,
           s.name || ' (' || s.team || ', ' || f.competition || '): ' || s.pts || ' puntos' AS jugador
    FROM f JOIN stats_player.stats_player s USING (match_id)
    WHERE s.pts IS NOT NULL
    ORDER BY f.fecha, s.pts DESC
)
SELECT to_char(f.fecha, 'DD/MM/YYYY') AS fecha,
       COUNT(*) AS partidos,
       COUNT(DISTINCT f.competition) AS ligas,
       SUM(f.home_score + f.away_score) AS puntos,
       COUNT(*) FILTER (WHERE ABS(f.home_score - f.away_score) <= 5) AS ajustados,
       mp.partido AS mas_puntos,
       md.partido AS mayor_diferencia,
       an.jugador AS maximo_anotador
FROM f
JOIN mas_puntos mp USING (fecha)
JOIN mayor_dif md USING (fecha)
LEFT JOIN anotador an USING (fecha)
GROUP BY f.fecha, mp.partido, md.partido, an.jugador
ORDER BY f.fecha DESC;
