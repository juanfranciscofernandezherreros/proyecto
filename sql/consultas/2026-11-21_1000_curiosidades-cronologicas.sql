-- =============================================================================
-- CURIOSIDADES EN ORDEN CRONOLÓGICO (UNA FILA POR CURIOSIDAD CON FECHA)
-- =============================================================================
-- Fecha:     2026-11-21 10:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-21_1000_curiosidades-cronologicas.sql
--            Filtros opcionales (psql): -v desde=2026-11-01 -v hasta=2026-11-20 -v liga=nba
--            (sin -v se ejecuta tal cual sobre todos los partidos).
--
-- PARA QUÉ SIRVE   Lo usa la skill `curiosidades`. Junta en una lista, del partido más
--                  antiguo al más reciente (fecha de Europe/Madrid), todo lo llamativo de
--                  cada partido, sacado de results.results (marcador y cuartos),
--                  point_by_point.point_by_point_event (marcador tras cada canasta) y
--                  stats_player.stats_player (línea de cada jugador).
--                  Mismas reglas que las consultas de rankings del 2026-11-20
--                  (2026-11-20_1000_partidos-ganados-tras-gran-remontada.sql,
--                  2026-11-20_2300_curiosidades-jugada-a-jugada.sql,
--                  2026-11-20_2330_curiosidades-resultados.sql,
--                  2026-11-20_2345_curiosidades-jugadores.sql): puntos de cada canasta por
--                  diferencia de marcador, rachas sin saltos de más de 3 puntos, jugador =
--                  nombre + equipo, estadísticas vacías = 0.
--                  Los récords «de la competición» se calculan sobre toda la temporada de esa
--                  competición, aunque se filtre por fechas.
--                  Limitaciones: el jugada a jugada no trae prórrogas ni reloj.
-- CUÁNDO USARLA    Para contar curiosidades (artículo, vídeo, bot) o tras cargar partidos.
-- CÓMO LEER EL RESULTADO
--   fecha      día del partido en Madrid; la lista va en orden cronológico.
--   liga       competición; partido = local marcador visitante (final de results).
--   tipo       remontada (ganó tras ir perdiendo de 15 o más) · racha (parcial de 15-0 o
--              más) · ultima canasta (ganó con la última canasta, sin prórroga) · igualdad
--              (15 o más cambios de líder) · de principio a fin (nunca fue por detrás y
--              ganó por 3 o menos) · paliza (35 o más) · cuarto record (más puntos de un
--              equipo en un cuarto en su competición) · parcial de cuarto (cuarto ganado
--              por 25 o más) · mas puntos / menos puntos (partido con más/menos puntos de
--              su competición) · prorroga · triple-doble · 40 puntos.
--   detalle    la frase con los datos de la curiosidad.
-- QUÉ HACER DESPUÉS  Un partido raro se revisa con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-21  447 curiosidades de 916 partidos, del 29/04/2026 (superleague) al
--                  20/11/2026: 119 rachas, 61 remontadas (= consulta de remontadas), 54
--                  prórrogas, 52 igualdad, 39 última canasta, 30 palizas, 30 de 40 puntos,
--                  13 triples-dobles, 13 cuartos récord, 11+11 más/menos puntos, 10 parciales
--                  de cuarto, 4 de principio a fin. Con -v desde=2026-11-01 -v liga=liga-endesa:
--                  9 filas (Girona-Bilbao 23 cambios de líder; Burgos 42 en un cuarto).
-- =============================================================================

-- PASO 0 · Valores por defecto de los filtros (si no se pasan con -v).
\if :{?desde}
\else
\set desde '1900-01-01'
\endif
\if :{?hasta}
\else
\set hasta '2999-12-31'
\endif
\if :{?liga}
\else
\set liga ''
\endif

-- PASO 1 · Todas las curiosidades con fecha, en orden cronológico.
WITH r AS (
    SELECT r.*, (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date AS fecha,
           CASE WHEN r.home_score > r.away_score THEN r.home_team ELSE r.away_team END AS ganador,
           CASE WHEN r.home_score > r.away_score THEN 'home' ELSE 'away' END AS lado,
           (r.home_score5 IS NOT NULL OR r.away_score5 IS NOT NULL) AS prorroga
    FROM results.results r
    WHERE r.home_score IS NOT NULL AND r.away_score IS NOT NULL
      AND r.event_datetime IS NOT NULL
),
-- Jugadas numeradas y puntos de cada canasta (diferencia con la jugada anterior).
ev AS (
    SELECT p.match_id, LEFT(p.quarter, 1)::int AS cuarto, p.sequence,
           p.home_score, p.away_score,
           ROW_NUMBER() OVER (PARTITION BY p.match_id ORDER BY p.quarter, p.sequence) AS n
    FROM point_by_point.point_by_point_event p
),
deltas AS (
    SELECT ev.*,
           home_score - COALESCE(LAG(home_score) OVER w, 0) AS dl,
           away_score - COALESCE(LAG(away_score) OVER w, 0) AS dv,
           ROW_NUMBER() OVER (PARTITION BY match_id ORDER BY n DESC) AS desde_final
    FROM ev
    WINDOW w AS (PARTITION BY match_id ORDER BY n)
),
-- 1 · Remontadas: mayor desventaja del ganador (15 o más).
remontada AS (
    SELECT DISTINCT ON (r.match_id) r.match_id, 1 AS orden, 'remontada' AS tipo,
           r.ganador || ' remontó ' || x.deficit || ' puntos (iba ' || d.home_score || '-'
           || d.away_score || ' en el ' || d.cuarto || 'º cuarto) y ganó' AS detalle,
           x.deficit
    FROM r
    JOIN deltas d USING (match_id)
    CROSS JOIN LATERAL (SELECT CASE WHEN r.lado = 'home' THEN d.away_score - d.home_score
                                    ELSE d.home_score - d.away_score END AS deficit) x
    WHERE r.home_score <> r.away_score
    ORDER BY r.match_id, x.deficit DESC, d.n
),
-- 2 · Rachas: puntos seguidos de un equipo sin respuesta (15-0 o más); la mayor del partido.
canastas AS (
    SELECT match_id, cuarto, n, home_score, away_score,
           CASE WHEN dl > 0 AND dv > 0 THEN 'ambos' WHEN dl > 0 THEN 'home' ELSE 'away' END AS anota,
           dl + dv AS puntos,
           ROW_NUMBER() OVER (PARTITION BY match_id ORDER BY n) AS m
    FROM deltas
    WHERE dl > 0 OR dv > 0
),
islas AS (
    SELECT *, m - ROW_NUMBER() OVER (PARTITION BY match_id, anota ORDER BY m) AS isla
    FROM canastas
),
rachas AS (
    SELECT match_id, anota, SUM(puntos) AS racha,
           MIN(cuarto) AS desde_cuarto, MAX(cuarto) AS hasta_cuarto,
           (ARRAY_AGG(home_score - CASE WHEN anota = 'home' THEN puntos ELSE 0 END ORDER BY m))[1] AS l_antes,
           (ARRAY_AGG(away_score - CASE WHEN anota = 'away' THEN puntos ELSE 0 END ORDER BY m))[1] AS v_antes,
           (ARRAY_AGG(home_score ORDER BY m DESC))[1] AS l_despues,
           (ARRAY_AGG(away_score ORDER BY m DESC))[1] AS v_despues,
           BOOL_AND(puntos BETWEEN 1 AND 3) AS limpia
    FROM islas
    GROUP BY match_id, anota, isla
),
racha AS (
    SELECT DISTINCT ON (ra.match_id) ra.match_id, 2 AS orden, 'racha' AS tipo,
           'Parcial de ' || ra.racha || '-0 de '
           || CASE WHEN ra.anota = 'home' THEN r.home_team ELSE r.away_team END
           || CASE WHEN ra.desde_cuarto = ra.hasta_cuarto THEN ' en el ' || ra.desde_cuarto || 'º cuarto'
                   ELSE ' entre el ' || ra.desde_cuarto || 'º y el ' || ra.hasta_cuarto || 'º cuarto' END
           || ' (de ' || ra.l_antes || '-' || ra.v_antes || ' a ' || ra.l_despues || '-' || ra.v_despues || ')' AS detalle
    FROM rachas ra
    JOIN r USING (match_id)
    WHERE ra.limpia AND ra.anota <> 'ambos' AND ra.racha >= 15
    ORDER BY ra.match_id, ra.racha DESC
),
-- 3 · Ganados con la última canasta (sin prórroga y con el jugada a jugada completo).
ultima AS (
    SELECT r.match_id, 3 AS orden, 'ultima canasta' AS tipo,
           r.ganador || ' ganó con la última canasta: iba ' || a.home_score || '-' || a.away_score
           || ' y acabó ' || r.home_score || '-' || r.away_score AS detalle
    FROM r
    JOIN deltas f ON f.match_id = r.match_id AND f.desde_final = 1
    JOIN deltas a ON a.match_id = r.match_id AND a.desde_final = 2
    WHERE NOT r.prorroga
      AND f.home_score = r.home_score AND f.away_score = r.away_score
      AND CASE WHEN r.lado = 'home' THEN a.home_score - a.away_score
               ELSE a.away_score - a.home_score END <= 0
),
-- 4 · Igualdad: 15 o más cambios de líder.
lideres AS (
    SELECT match_id, SIGN(home_score - away_score) AS lider,
           LAG(SIGN(home_score - away_score)) OVER (PARTITION BY match_id ORDER BY n) AS previo
    FROM deltas WHERE home_score <> away_score
),
igualdad AS (
    SELECT c.match_id, 4 AS orden, 'igualdad' AS tipo,
           c.cambios || ' cambios de líder y ' || e.empates || ' empates' AS detalle
    FROM (SELECT match_id, COUNT(*) FILTER (WHERE lider <> previo) AS cambios
          FROM lideres GROUP BY match_id) c
    JOIN (SELECT match_id, COUNT(*) FILTER (WHERE home_score = away_score) AS empates
          FROM deltas GROUP BY match_id) e USING (match_id)
    WHERE c.cambios >= 15
),
-- 5 · De principio a fin y ajustado: el ganador nunca fue por detrás y ganó por 3 o menos.
principio_fin AS (
    SELECT r.match_id, 5 AS orden, 'de principio a fin' AS tipo,
           r.ganador || ' no fue por detrás en ningún momento y ganó por solo '
           || ABS(r.home_score - r.away_score) AS detalle
    FROM r
    JOIN remontada re USING (match_id)
    WHERE re.deficit <= 0 AND ABS(r.home_score - r.away_score) <= 3
),
-- 6 · Palizas: 35 puntos o más.
paliza AS (
    SELECT match_id, 6 AS orden, 'paliza' AS tipo,
           ganador || ' ganó por ' || ABS(home_score - away_score) || ' puntos' AS detalle
    FROM r WHERE ABS(home_score - away_score) >= 35
),
-- 7 · Cuartos: récord de puntos de un equipo en un cuarto en su competición, y cuartos
--     ganados por 25 o más.
cuartos AS (
    SELECT r.match_id, r.competition, c.cuarto, c.propios, c.rival, c.equipo,
           RANK() OVER (PARTITION BY r.competition ORDER BY c.propios DESC) AS rk
    FROM r
    CROSS JOIN LATERAL (VALUES
        (1, r.home_score1, r.away_score1, r.home_team), (2, r.home_score2, r.away_score2, r.home_team),
        (3, r.home_score3, r.away_score3, r.home_team), (4, r.home_score4, r.away_score4, r.home_team),
        (1, r.away_score1, r.home_score1, r.away_team), (2, r.away_score2, r.home_score2, r.away_team),
        (3, r.away_score3, r.home_score3, r.away_team), (4, r.away_score4, r.home_score4, r.away_team)
    ) AS c(cuarto, propios, rival, equipo)
    WHERE c.propios IS NOT NULL AND c.rival IS NOT NULL
),
cuarto_record AS (
    SELECT match_id, 7 AS orden, 'cuarto record' AS tipo,
           equipo || ' metió ' || propios || ' puntos en el ' || cuarto
           || 'º cuarto (' || propios || '-' || rival || '), récord de la competición' AS detalle
    FROM cuartos WHERE rk = 1
),
parcial_cuarto AS (
    SELECT DISTINCT ON (match_id) match_id, 8 AS orden, 'parcial de cuarto' AS tipo,
           equipo || ' ganó el ' || cuarto || 'º cuarto ' || propios || '-' || rival
           || ' (+' || (propios - rival) || ')' AS detalle
    FROM cuartos WHERE propios - rival >= 25
    ORDER BY match_id, propios - rival DESC
),
-- 8 · Partido con más y con menos puntos de su competición.
totales AS (
    SELECT match_id, home_score + away_score AS total,
           RANK() OVER (PARTITION BY competition ORDER BY home_score + away_score DESC) AS rk_max,
           RANK() OVER (PARTITION BY competition ORDER BY home_score + away_score ASC) AS rk_min
    FROM r
),
extremos AS (
    SELECT match_id, 9 AS orden, 'mas puntos' AS tipo,
           total || ' puntos entre los dos: el partido con más puntos de la competición' AS detalle
    FROM totales WHERE rk_max = 1
    UNION ALL
    SELECT match_id, 10, 'menos puntos',
           total || ' puntos entre los dos: el partido con menos puntos de la competición'
    FROM totales WHERE rk_min = 1
),
-- 9 · Prórroga.
prorroga AS (
    SELECT match_id, 11 AS orden, 'prorroga' AS tipo,
           'Se fue a la prórroga (' || (home_score - COALESCE(home_score5, 0)) || '-'
           || (away_score - COALESCE(away_score5, 0)) || ' al final del 4º cuarto)' AS detalle
    FROM r WHERE prorroga
),
-- 10 · Jugadores: triples-dobles y partidos de 40 puntos o más.
lineas AS (
    SELECT s.match_id, s.name, s.team,
           COALESCE(s.pts, 0) AS pts, COALESCE(s.reb, 0) AS reb, COALESCE(s.ast, 0) AS ast,
           COALESCE(s.st, 0) AS rob, COALESCE(s.bs, 0) AS tap,
           COALESCE(s.threepm, 0) AS t3, COALESCE(s.threepa, 0) AS t3a
    FROM stats_player.stats_player s
),
jugadores AS (
    SELECT match_id, 12 AS orden, 'triple-doble' AS tipo,
           name || ' (' || team || '): ' || pts || ' puntos, ' || reb || ' rebotes, ' || ast
           || ' asistencias' || CASE WHEN rob >= 10 THEN ', ' || rob || ' robos' ELSE '' END
           || CASE WHEN tap >= 10 THEN ', ' || tap || ' tapones' ELSE '' END AS detalle
    FROM lineas
    WHERE (pts >= 10)::int + (reb >= 10)::int + (ast >= 10)::int + (rob >= 10)::int + (tap >= 10)::int >= 3
    UNION ALL
    SELECT match_id, 13, '40 puntos',
           name || ' (' || team || ') anotó ' || pts || ' puntos (' || t3 || '/' || t3a
           || ' en triples, ' || reb || ' rebotes y ' || ast || ' asistencias)'
    FROM lineas WHERE pts >= 40
),
todas AS (
    SELECT match_id, orden, tipo, detalle FROM remontada WHERE deficit >= 15
    UNION ALL SELECT * FROM racha
    UNION ALL SELECT * FROM ultima
    UNION ALL SELECT * FROM igualdad
    UNION ALL SELECT * FROM principio_fin
    UNION ALL SELECT * FROM paliza
    UNION ALL SELECT * FROM cuarto_record
    UNION ALL SELECT * FROM parcial_cuarto
    UNION ALL SELECT * FROM extremos
    UNION ALL SELECT * FROM prorroga
    UNION ALL SELECT * FROM jugadores
)
SELECT to_char(r.fecha, 'DD/MM/YYYY') AS fecha,
       r.competition AS liga,
       r.home_team || ' ' || r.home_score || '-' || r.away_score || ' ' || r.away_team AS partido,
       t.tipo,
       t.detalle,
       r.match_id
FROM todas t
JOIN r USING (match_id)
WHERE r.fecha BETWEEN :'desde'::date AND :'hasta'::date
  AND (:'liga' = '' OR r.competition = :'liga')
ORDER BY r.event_datetime, r.match_id, t.orden, t.detalle;
