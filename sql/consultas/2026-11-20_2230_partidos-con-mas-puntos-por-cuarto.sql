-- =============================================================================
-- PARTIDOS CON MÁS PUNTOS EN CADA CUARTO
-- =============================================================================
-- Fecha:     2026-11-20 22:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-20_2230_partidos-con-mas-puntos-por-cuarto.sql
--
-- PARA QUÉ SIRVE   Ranking, cuarto a cuarto, de los partidos en que más puntos se anotaron
--                  entre los dos equipos. Sale de results.results, que guarda los puntos
--                  de cada periodo por equipo (home_score1..4 / away_score1..4; el 5 es la
--                  prórroga y aquí no entra). No necesita jugada a jugada, así que cubre
--                  todos los partidos con resultado, no solo los 888 con jugadas.
-- CUÁNDO USARLA    Para curiosidades/artículos o tras cargar resultados nuevos.
-- CÓMO LEER EL RESULTADO
--   cuarto        1 a 4
--   puesto        posición dentro del cuarto (RANK: los empates comparten puesto, por eso
--                 un cuarto puede tener más de 10 filas)
--   puntos        local + visitante en ese cuarto
--   local/visit.  puntos de cada equipo en ese cuarto
--   PASO 2: si un cuarto suma más de 90, o un equipo más de 60, casi seguro es un dato mal
--   extraído (en la NBA el récord de un equipo en un cuarto ronda los 50).
-- QUÉ HACER DESPUÉS  Un partido sospechoso se revisa con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-20  893 partidos con puntos por cuarto; 46 filas (empates incluidos).
--                  Máximos: 1º OKC-Bucks 79 (44-35); 2º Pelicans-Nets 85 (41-44);
--                  3º empate a 83 (Breogan-Burgos, Suns-Warriors, Bucks-Bulls);
--                  4º Pistons-Raptors 81 (36-45). Casi todo es NBA (cuartos de 12 min,
--                  no de 10). PASO 2: 0 filas, ningún cuarto sospechoso ni descuadrado.
-- =============================================================================

-- PASO 1 · Los 10 partidos con más puntos (los dos equipos) en cada cuarto.
WITH cuartos AS (
    SELECT r.match_id, r.event_datetime, r.competition, r.home_team, r.away_team,
           r.home_score, r.away_score, c.cuarto, c.local, c.visitante
    FROM results.results r
    CROSS JOIN LATERAL (VALUES
        (1, r.home_score1, r.away_score1),
        (2, r.home_score2, r.away_score2),
        (3, r.home_score3, r.away_score3),
        (4, r.home_score4, r.away_score4)
    ) AS c(cuarto, local, visitante)
    WHERE c.local IS NOT NULL AND c.visitante IS NOT NULL
),
ranking AS (
    SELECT *, local + visitante AS puntos,
           RANK() OVER (PARTITION BY cuarto ORDER BY local + visitante DESC) AS puesto
    FROM cuartos
)
SELECT cuarto, puesto, puntos,
       local || '-' || visitante AS cuarto_local_visit,
       home_team || ' - ' || away_team AS partido,
       home_score || '-' || away_score AS final,
       competition, event_datetime::date AS fecha, match_id
FROM ranking
WHERE puesto <= 10
ORDER BY cuarto, puesto, event_datetime DESC;

-- PASO 2 · Control de calidad: cuartos con valores imposibles o sospechosos, y cuartos
--          que no cuadran con el marcador final (sin prórroga).
SELECT match_id, home_team || ' - ' || away_team AS partido, competition,
       home_score1, home_score2, home_score3, home_score4, home_score5, home_score,
       away_score1, away_score2, away_score3, away_score4, away_score5, away_score
FROM results.results
WHERE GREATEST(home_score1, home_score2, home_score3, home_score4,
               away_score1, away_score2, away_score3, away_score4) > 60
   OR GREATEST(home_score1 + away_score1, home_score2 + away_score2,
               home_score3 + away_score3, home_score4 + away_score4) > 90
   OR (home_score5 IS NULL AND away_score5 IS NULL
       AND home_score1 IS NOT NULL AND away_score1 IS NOT NULL
       AND (home_score1 + home_score2 + home_score3 + home_score4 <> home_score
         OR away_score1 + away_score2 + away_score3 + away_score4 <> away_score));
