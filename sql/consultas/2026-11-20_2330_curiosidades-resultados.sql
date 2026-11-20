-- =============================================================================
-- CURIOSIDADES DE LOS RESULTADOS: EQUIPOS POR CUARTO, PALIZAS, PRÓRROGAS Y TOTALES
-- =============================================================================
-- Fecha:     2026-11-20 23:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-20_2330_curiosidades-resultados.sql
--
-- PARA QUÉ SIRVE   Rankings sacados solo de results.results (marcador final y puntos de
--                  cada periodo por equipo: *_score1..4 los cuartos, *_score5 la prórroga).
--                  Cubre todos los partidos con resultado, no solo los que tienen jugadas.
--                  Ver también 2026-11-20_2230_partidos-con-mas-puntos-por-cuarto.sql.
-- CUÁNDO USARLA    Para curiosidades/artículos o tras cargar resultados nuevos.
-- CÓMO LEER EL RESULTADO
--   PASO 1  dif_c1..dif_c4 = diferencia media (puntos propios − del rival) del equipo en
--           cada cuarto. Mínimo 5 partidos. 1a: los que mejor arrancan (1er cuarto);
--           1b: los que mejor acaban (4º cuarto).
--   PASO 2  2a: mayores diferencias finales; 2b: mayor diferencia en un solo cuarto.
--   PASO 3  prórrogas por competición. Solo hay una columna de prórroga (*_score5), así
--           que no se distingue una prórroga de varias.
--   PASO 4  por competición: media de puntos totales y los partidos de más y menos puntos.
--           La NBA juega cuartos de 12 minutos y el resto de 10: no comparar entre ellas.
-- QUÉ HACER DESPUÉS  Un partido raro se revisa con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-20  1a: Maccabi Tel Aviv +9,0 en el 1º. 1b: Paris y Galatasaray
--                  +6,3 en el 4º. 2a: Crvena Zvezda 116-62 Zlatibor (54). 2b: Celtics 42-9
--                  a Dallas en el 1º (33). 3: 51 de 893 con prórroga (5,7 %; LNB 10,6 %).
--                  4: NBA 228,1 de media; máximo Wizards 140-144 Pistons (284).
-- =============================================================================

-- PASO 1a · Equipos que mejor arrancan: diferencia media en el 1er cuarto.
WITH por_equipo AS (
    SELECT competition, home_team AS equipo,
           home_score1 - away_score1 AS d1, home_score2 - away_score2 AS d2,
           home_score3 - away_score3 AS d3, home_score4 - away_score4 AS d4
    FROM results.results WHERE home_score4 IS NOT NULL AND away_score4 IS NOT NULL
    UNION ALL
    SELECT competition, away_team,
           away_score1 - home_score1, away_score2 - home_score2,
           away_score3 - home_score3, away_score4 - home_score4
    FROM results.results WHERE home_score4 IS NOT NULL AND away_score4 IS NOT NULL
),
medias AS (
    SELECT equipo, competition, COUNT(*) AS partidos,
           ROUND(AVG(d1), 1) AS dif_c1, ROUND(AVG(d2), 1) AS dif_c2,
           ROUND(AVG(d3), 1) AS dif_c3, ROUND(AVG(d4), 1) AS dif_c4
    FROM por_equipo GROUP BY equipo, competition HAVING COUNT(*) >= 5
)
SELECT * FROM medias ORDER BY dif_c1 DESC, equipo LIMIT 10;

-- PASO 1b · Equipos que mejor acaban: diferencia media en el 4º cuarto.
WITH por_equipo AS (
    SELECT competition, home_team AS equipo,
           home_score1 - away_score1 AS d1, home_score2 - away_score2 AS d2,
           home_score3 - away_score3 AS d3, home_score4 - away_score4 AS d4
    FROM results.results WHERE home_score4 IS NOT NULL AND away_score4 IS NOT NULL
    UNION ALL
    SELECT competition, away_team,
           away_score1 - home_score1, away_score2 - home_score2,
           away_score3 - home_score3, away_score4 - home_score4
    FROM results.results WHERE home_score4 IS NOT NULL AND away_score4 IS NOT NULL
),
medias AS (
    SELECT equipo, competition, COUNT(*) AS partidos,
           ROUND(AVG(d1), 1) AS dif_c1, ROUND(AVG(d2), 1) AS dif_c2,
           ROUND(AVG(d3), 1) AS dif_c3, ROUND(AVG(d4), 1) AS dif_c4
    FROM por_equipo GROUP BY equipo, competition HAVING COUNT(*) >= 5
)
SELECT * FROM medias ORDER BY dif_c4 DESC, equipo LIMIT 10;

-- PASO 2a · Mayores palizas: diferencia final.
SELECT ABS(home_score - away_score) AS diferencia,
       CASE WHEN home_score > away_score THEN home_team ELSE away_team END AS ganador,
       home_team || ' - ' || away_team AS partido,
       home_score || '-' || away_score AS final,
       competition, event_datetime::date AS fecha, match_id
FROM results.results
WHERE home_score IS NOT NULL AND away_score IS NOT NULL
ORDER BY diferencia DESC, event_datetime DESC
LIMIT 10;

-- PASO 2b · Mayor diferencia en un solo cuarto.
SELECT ABS(c.local - c.visitante) AS diferencia, c.cuarto,
       c.local || '-' || c.visitante AS parcial,
       CASE WHEN c.local > c.visitante THEN r.home_team ELSE r.away_team END AS gana_el_cuarto,
       r.home_team || ' - ' || r.away_team AS partido,
       r.home_score || '-' || r.away_score AS final,
       r.competition, r.event_datetime::date AS fecha, r.match_id
FROM results.results r
CROSS JOIN LATERAL (VALUES
    (1, r.home_score1, r.away_score1), (2, r.home_score2, r.away_score2),
    (3, r.home_score3, r.away_score3), (4, r.home_score4, r.away_score4)
) AS c(cuarto, local, visitante)
WHERE c.local IS NOT NULL AND c.visitante IS NOT NULL
ORDER BY diferencia DESC, r.event_datetime DESC
LIMIT 10;

-- PASO 3 · Prórrogas por competición (y en total).
SELECT COALESCE(competition, 'TOTAL') AS competicion,
       COUNT(*) AS partidos,
       COUNT(*) FILTER (WHERE home_score5 IS NOT NULL OR away_score5 IS NOT NULL) AS con_prorroga,
       ROUND(100.0 * COUNT(*) FILTER (WHERE home_score5 IS NOT NULL OR away_score5 IS NOT NULL)
             / COUNT(*), 1) AS pct,
       MAX(GREATEST(home_score5, away_score5)) AS max_puntos_equipo_en_prorroga
FROM results.results
WHERE home_score IS NOT NULL AND away_score IS NOT NULL
GROUP BY ROLLUP (competition)
ORDER BY competition NULLS LAST;

-- PASO 4 · Puntos totales por competición: media, y el partido con más y con menos puntos.
WITH t AS (
    SELECT competition, match_id, home_score + away_score AS total,
           home_team || ' ' || home_score || '-' || away_score || ' ' || away_team AS partido,
           ROW_NUMBER() OVER (PARTITION BY competition ORDER BY home_score + away_score DESC, event_datetime DESC) AS rk_max,
           ROW_NUMBER() OVER (PARTITION BY competition ORDER BY home_score + away_score ASC, event_datetime DESC) AS rk_min
    FROM results.results
    WHERE home_score IS NOT NULL AND away_score IS NOT NULL
)
SELECT competition, COUNT(*) AS partidos, ROUND(AVG(total), 1) AS media_total,
       MAX(total) AS max_total, MAX(partido) FILTER (WHERE rk_max = 1) AS partido_max,
       MIN(total) AS min_total, MAX(partido) FILTER (WHERE rk_min = 1) AS partido_min
FROM t
GROUP BY competition
ORDER BY media_total DESC;
