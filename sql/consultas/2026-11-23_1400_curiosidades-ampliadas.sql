-- =============================================================================
-- CURIOSIDADES AMPLIADAS, CON NIVEL DE DESTACADO, DE LA MÁS NUEVA A LA MÁS ANTIGUA
-- =============================================================================
-- Fecha:     2026-11-23 14:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-23_1400_curiosidades-ampliadas.sql
--            Filtros opcionales (psql): -v desde=2026-11-01 -v hasta=2026-11-20 -v liga=nba
--            -v nivel=2 (solo nivel 2 o más). Sin -v se ejecuta tal cual sobre todo.
--
-- PARA QUÉ SIRVE   Lo usa la skill `curiosidades` (y los guiones de vídeo). Sustituye a
--                  2026-11-21_1000_curiosidades-cronologicas.sql: mismos 13 tipos con las
--                  mismas reglas, más 17 tipos nuevos (partido, jugadores y rachas de
--                  equipo), una columna `nivel` para ver lo más destacado y el orden
--                  invertido: primero el partido más reciente.
--                  Fuentes: results.results (marcador, cuartos), point_by_point.point_by_point_event
--                  (marcador tras cada canasta) y stats_player.stats_player (línea de cada
--                  jugador; jugador = nombre + equipo, vacíos = 0).
--                  Umbrales fijados con 2026-11-23_1330_curiosidades-ampliadas-exploracion.sql.
--                  Limitaciones: el jugada a jugada no trae prórrogas ni reloj (no hay
--                  sequías); stats_player no distingue titulares; una sola columna de prórroga.
--                  Récords, rachas y % de victorias se calculan sobre toda la temporada
--                  cargada de cada competición, aunque se filtre por fechas.
-- CUÁNDO USARLA    Para contar curiosidades (artículo, vídeo, bot) o tras cargar partidos.
-- CÓMO LEER EL RESULTADO
--   fecha      día del partido en Madrid; la lista va del más reciente al más antiguo.
--   nivel      3 = excepcional (récords, remontadas o parciales de 25+, 50 puntos, 20-20…),
--              2 = muy destacada, 1 = curiosa. Dentro de un partido, primero el nivel alto.
--   liga, partido (local marcador visitante), tipo, detalle (la frase con los datos), match_id.
--   Tipos (orden dentro del partido):
--     PARTIDO   remontada (15+) · racha (parcial 15-0+) · ultima canasta · igualdad (15+
--               cambios de líder) · de principio a fin (nunca detrás, ganó por 3 o menos) ·
--               paliza (35+) · cuarto record · parcial de cuarto (25+) · mas/menos puntos ·
--               prorroga · gano perdiendo cuartos (perdió 3 o 4 de los 4 cuartos) ·
--               cuarto en blanco (un equipo con 7 o menos en un cuarto).
--     JUGADOR   triple-doble · 40 puntos · 20-20 · exhibicion (20+ reb, 15+ ast, 8+
--               triples, 6+ tapones, 6+ robos) · tiro perfecto (8+ tiros de campo sin
--               fallo) · negado (0 de 8+ triples o 0 de 10+ de campo) · tiros libres (15+
--               sin fallo o 20+ lanzados) · perdidas (10+) · maraton (48+ minutos) ·
--               mejor marca (máximo de la temporada del jugador, 25+, con 5+ partidos
--               antes, superando su anterior máximo en 5+) · doble turno (20+ puntos en
--               dos competiciones distintas en 3 días).
--     EQUIPO    racha de victorias (8.ª, 10.ª, 12.ª, 15.ª, 20.ª… seguidas) · racha cortada
--               (pierde quien llevaba 8+ seguidas) · sorpresa (gana el que tenía 40+
--               puntos menos de % de victorias, 6+ partidos cada uno) · back-to-back (NBA:
--               gana por 15+ con menos de 30 h desde su partido anterior).
-- QUÉ HACER DESPUÉS  Un dato raro se revisa con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-23  649 curiosidades (nivel 3: 73, nivel 2: 203, nivel 1: 373), del
--                  23/11/2026 al 29/04/2026. Por tipo: 110 rachas, 55 remontadas, 53
--                  prórrogas, 51 igualdad, 42 exhibiciones, 39 última canasta, 34 ganó
--                  perdiendo cuartos, 33 de 40 puntos, 31 palizas, 28 mejor marca, 27
--                  sorpresas, 23 cuartos en blanco, 12 triples-dobles, 12 negados, 12
--                  cuartos récord, 11 parciales de cuarto, 11+11 más/menos puntos, 11 doble
--                  turno, 11 back-to-back, 9 rachas de victorias, 5 tiros libres, 5 tiro
--                  perfecto, 4 de principio a fin, 3 rachas cortadas, 2 pérdidas, 2 maratón,
--                  2 20-20. Sin el corte de pretemporada salían 774 y récords NBA falsos
--                  (49 en un cuarto el 06/10, Kings «1-19»). Revisión a mano de 5 de nivel 3:
--                  2026-11-23_1500_curiosidades-revision-destacadas.sql (todas cuadran).
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
\if :{?nivel}
\else
\set nivel 1
\endif

-- PASO 1 · Todas las curiosidades con nivel, de la más nueva a la más antigua.
WITH r AS (
    SELECT r.*, (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date AS fecha,
           CASE WHEN r.home_score > r.away_score THEN r.home_team ELSE r.away_team END AS ganador,
           CASE WHEN r.home_score > r.away_score THEN r.away_team ELSE r.home_team END AS perdedor,
           CASE WHEN r.home_score > r.away_score THEN 'home' ELSE 'away' END AS lado,
           (r.home_score5 IS NOT NULL OR r.away_score5 IS NOT NULL) AS prorroga
    FROM results.results r
    WHERE r.home_score IS NOT NULL AND r.away_score IS NOT NULL
      AND r.event_datetime IS NOT NULL
      -- Sin la pretemporada de la NBA (mismo corte que RegularSeason de la API): falseaba
      -- récords (49 en un cuarto el 06/10), palizas, rachas y % de victorias.
      AND NOT (r.competition = 'nba' AND r.event_datetime < TIMESTAMPTZ '2026-10-19 22:00:00+00')
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
           CASE WHEN x.deficit >= 25 THEN 3 WHEN x.deficit >= 20 THEN 2 ELSE 1 END AS nivel,
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
           || ' (de ' || ra.l_antes || '-' || ra.v_antes || ' a ' || ra.l_despues || '-' || ra.v_despues || ')' AS detalle,
           CASE WHEN ra.racha >= 25 THEN 3 WHEN ra.racha >= 20 THEN 2 ELSE 1 END AS nivel
    FROM rachas ra
    JOIN r USING (match_id)
    WHERE ra.limpia AND ra.anota <> 'ambos' AND ra.racha >= 15
    ORDER BY ra.match_id, ra.racha DESC
),
-- 3 · Ganados con la última canasta (sin prórroga y con el jugada a jugada completo).
ultima AS (
    SELECT r.match_id, 3 AS orden, 'ultima canasta' AS tipo,
           r.ganador || ' ganó con la última canasta: iba ' || a.home_score || '-' || a.away_score
           || ' y acabó ' || r.home_score || '-' || r.away_score AS detalle,
           2 AS nivel
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
           c.cambios || ' cambios de líder y ' || e.empates || ' empates' AS detalle,
           CASE WHEN c.cambios >= 25 THEN 3 WHEN c.cambios >= 20 THEN 2 ELSE 1 END AS nivel
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
           || ABS(r.home_score - r.away_score) AS detalle,
           1 AS nivel
    FROM r
    JOIN remontada re USING (match_id)
    WHERE re.deficit <= 0 AND ABS(r.home_score - r.away_score) <= 3
),
-- 6 · Palizas: 35 puntos o más.
paliza AS (
    SELECT match_id, 6 AS orden, 'paliza' AS tipo,
           ganador || ' ganó por ' || ABS(home_score - away_score) || ' puntos' AS detalle,
           CASE WHEN ABS(home_score - away_score) >= 50 THEN 3
                WHEN ABS(home_score - away_score) >= 45 THEN 2 ELSE 1 END AS nivel
    FROM r WHERE ABS(home_score - away_score) >= 35
),
-- 7 · Cuartos: récord de puntos de un equipo en un cuarto en su competición, cuartos
--     ganados por 25 o más y cuartos de 7 puntos o menos.
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
           || 'º cuarto (' || propios || '-' || rival || '), récord de la competición' AS detalle,
           3 AS nivel
    FROM cuartos WHERE rk = 1
),
parcial_cuarto AS (
    SELECT DISTINCT ON (match_id) match_id, 8 AS orden, 'parcial de cuarto' AS tipo,
           equipo || ' ganó el ' || cuarto || 'º cuarto ' || propios || '-' || rival
           || ' (+' || (propios - rival) || ')' AS detalle,
           CASE WHEN propios - rival >= 30 THEN 2 ELSE 1 END AS nivel
    FROM cuartos WHERE propios - rival >= 25
    ORDER BY match_id, propios - rival DESC
),
cuarto_blanco AS (
    SELECT DISTINCT ON (match_id) match_id, 9 AS orden, 'cuarto en blanco' AS tipo,
           equipo || ' solo anotó ' || propios || ' puntos en el ' || cuarto
           || 'º cuarto (' || propios || '-' || rival || ')' AS detalle,
           CASE WHEN propios <= 5 THEN 2 ELSE 1 END AS nivel
    FROM cuartos WHERE propios <= 7
    ORDER BY match_id, propios
),
-- 8 · Partido con más y con menos puntos de su competición.
totales AS (
    SELECT match_id, home_score + away_score AS total,
           RANK() OVER (PARTITION BY competition ORDER BY home_score + away_score DESC) AS rk_max,
           RANK() OVER (PARTITION BY competition ORDER BY home_score + away_score ASC) AS rk_min
    FROM r
),
extremos AS (
    SELECT match_id, 10 AS orden, 'mas puntos' AS tipo,
           total || ' puntos entre los dos: el partido con más puntos de la competición' AS detalle,
           3 AS nivel
    FROM totales WHERE rk_max = 1
    UNION ALL
    SELECT match_id, 11, 'menos puntos',
           total || ' puntos entre los dos: el partido con menos puntos de la competición', 3
    FROM totales WHERE rk_min = 1
),
-- 9 · Prórroga.
prorroga AS (
    SELECT match_id, 12 AS orden, 'prorroga' AS tipo,
           'Se fue a la prórroga (' || (home_score - COALESCE(home_score5, 0)) || '-'
           || (away_score - COALESCE(away_score5, 0)) || ' al final del 4º cuarto)' AS detalle,
           1 AS nivel
    FROM r WHERE prorroga
),
-- 10 · Ganó perdiendo 3 o 4 de los 4 cuartos.
perdidos AS (
    SELECT r.match_id, r.ganador,
           CASE WHEN r.lado = 'home'
                THEN (r.home_score1 < r.away_score1)::int + (r.home_score2 < r.away_score2)::int
                   + (r.home_score3 < r.away_score3)::int + (r.home_score4 < r.away_score4)::int
                ELSE (r.away_score1 < r.home_score1)::int + (r.away_score2 < r.home_score2)::int
                   + (r.away_score3 < r.home_score3)::int + (r.away_score4 < r.home_score4)::int END AS n
    FROM r WHERE r.home_score4 IS NOT NULL AND r.away_score4 IS NOT NULL
),
gano_perdiendo AS (
    SELECT match_id, 13 AS orden, 'gano perdiendo cuartos' AS tipo,
           ganador || ' ganó perdiendo ' || n || ' de los 4 cuartos' AS detalle,
           CASE WHEN n = 4 THEN 3 ELSE 1 END AS nivel
    FROM perdidos WHERE n >= 3
),
-- 11 · Jugadores: línea de cada uno con fecha y competición del partido.
lineas AS (
    SELECT s.match_id, s.name, s.team, r.competition, r.event_datetime,
           COALESCE(s.pts, 0) AS pts, COALESCE(s.reb, 0) AS reb, COALESCE(s.ast, 0) AS ast,
           COALESCE(s.st, 0) AS rob, COALESCE(s.bs, 0) AS tap,
           COALESCE(s.fgm, 0) AS tc, COALESCE(s.fga, 0) AS tca,
           COALESCE(s.threepm, 0) AS t3, COALESCE(s.threepa, 0) AS t3a,
           COALESCE(s.ftm, 0) AS tl, COALESCE(s.fta, 0) AS tla,
           COALESCE(s.turnovers, 0) AS per,
           substring(s.min from '^[0-9]+')::int AS minutos
    FROM stats_player.stats_player s
    JOIN r USING (match_id)
),
jugadores AS (
    SELECT match_id, 20 AS orden, 'triple-doble' AS tipo,
           name || ' (' || team || '): ' || pts || ' puntos, ' || reb || ' rebotes, ' || ast
           || ' asistencias' || CASE WHEN rob >= 10 THEN ', ' || rob || ' robos' ELSE '' END
           || CASE WHEN tap >= 10 THEN ', ' || tap || ' tapones' ELSE '' END AS detalle,
           CASE WHEN pts >= 30 OR reb >= 15 OR ast >= 15 THEN 3 ELSE 2 END AS nivel
    FROM lineas
    WHERE (pts >= 10)::int + (reb >= 10)::int + (ast >= 10)::int + (rob >= 10)::int + (tap >= 10)::int >= 3
    UNION ALL
    SELECT match_id, 21, '40 puntos',
           name || ' (' || team || ') anotó ' || pts || ' puntos (' || t3 || '/' || t3a
           || ' en triples, ' || reb || ' rebotes y ' || ast || ' asistencias)',
           CASE WHEN pts >= 50 THEN 3 ELSE 2 END
    FROM lineas WHERE pts >= 40
    UNION ALL
    SELECT match_id, 22, '20-20',
           name || ' (' || team || '): ' || pts || ' puntos y ' || reb || ' rebotes', 3
    FROM lineas WHERE pts >= 20 AND reb >= 20
    UNION ALL
    SELECT match_id, 23, 'exhibicion',
           name || ' (' || team || '): '
           || concat_ws(', ',
                CASE WHEN reb >= 20 AND pts < 20 THEN reb || ' rebotes' END,
                CASE WHEN ast >= 15 THEN ast || ' asistencias' END,
                CASE WHEN t3 >= 8 THEN t3 || ' triples (' || t3 || '/' || t3a || ')' END,
                CASE WHEN tap >= 6 THEN tap || ' tapones' END,
                CASE WHEN rob >= 6 THEN rob || ' robos' END)
           || ' (' || pts || ' puntos)',
           CASE WHEN t3 >= 10 OR reb >= 25 OR ast >= 20 OR tap >= 8 OR rob >= 8 THEN 3 ELSE 2 END
    FROM lineas WHERE (reb >= 20 AND pts < 20) OR ast >= 15 OR t3 >= 8 OR tap >= 6 OR rob >= 6
    UNION ALL
    SELECT match_id, 24, 'tiro perfecto',
           name || ' (' || team || ') no falló ningún tiro de campo: ' || tc || '/' || tca
           || ' (' || t3 || '/' || t3a || ' en triples) y ' || pts || ' puntos',
           CASE WHEN tca >= 10 THEN 3 ELSE 2 END
    FROM lineas WHERE tca >= 8 AND tc = tca
    UNION ALL
    SELECT match_id, 25, 'negado',
           name || ' (' || team || ') ' ||
           CASE WHEN tca >= 10 AND tc = 0 THEN 'no metió ninguno de sus ' || tca || ' tiros de campo'
                ELSE 'falló sus ' || t3a || ' triples (' || pts || ' puntos)' END,
           1
    FROM lineas WHERE (t3a >= 8 AND t3 = 0) OR (tca >= 10 AND tc = 0)
    UNION ALL
    SELECT match_id, 26, 'tiros libres',
           name || ' (' || team || ') ' ||
           CASE WHEN tla >= 15 AND tl = tla THEN 'metió sus ' || tla || ' tiros libres sin fallar'
                ELSE 'lanzó ' || tla || ' tiros libres (' || tl || ' dentro)' END
           || ', ' || pts || ' puntos',
           1
    FROM lineas WHERE (tla >= 15 AND tl = tla) OR tla >= 20
    UNION ALL
    SELECT match_id, 27, 'perdidas',
           name || ' (' || team || ') perdió ' || per || ' balones', 1
    FROM lineas WHERE per >= 10
    UNION ALL
    SELECT match_id, 28, 'maraton',
           name || ' (' || team || ') jugó ' || minutos || ' minutos (' || pts || ' puntos)',
           CASE WHEN minutos >= 50 THEN 2 ELSE 1 END
    FROM lineas WHERE minutos >= 48
),
-- 12 · Mejor marca: máximo de puntos de la temporada del jugador (nombre + equipo).
marcas AS (
    SELECT l.*,
           MAX(pts) OVER w AS max_antes,
           COUNT(*) OVER w AS partidos_antes
    FROM lineas l
    WINDOW w AS (PARTITION BY name, team, competition ORDER BY event_datetime
                 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
),
mejor_marca AS (
    SELECT match_id, 29 AS orden, 'mejor marca' AS tipo,
           name || ' (' || team || ') hizo su mejor partido de la temporada: ' || pts
           || ' puntos (su máximo era ' || max_antes || ' en ' || partidos_antes || ' partidos)' AS detalle,
           CASE WHEN pts - max_antes >= 10 THEN 2 ELSE 1 END AS nivel
    FROM marcas
    WHERE pts >= 30 AND partidos_antes >= 5 AND pts - max_antes >= 8
),
-- 13 · Doble turno: 20+ puntos en dos competiciones distintas con 3 días o menos entre medias.
doble_turno AS (
    SELECT DISTINCT ON (b.match_id, b.name) b.match_id, 30 AS orden, 'doble turno' AS tipo,
           b.name || ' (' || b.team || '): ' || b.pts || ' puntos aquí y ' || a.pts || ' en '
           || a.competition || ' ' || EXTRACT(DAY FROM (b.event_datetime - a.event_datetime))::int
           || ' día(s) antes' AS detalle,
           2 AS nivel
    FROM lineas a
    JOIN lineas b ON b.name = a.name AND b.team = a.team AND b.competition <> a.competition
                 AND b.event_datetime > a.event_datetime
                 AND b.event_datetime - a.event_datetime <= interval '3 days'
    WHERE a.pts >= 20 AND b.pts >= 20
    ORDER BY b.match_id, b.name, a.event_datetime DESC
),
-- 14 · Equipos: partidos de cada equipo en su competición, en orden, con racha y % previo.
eq AS (
    SELECT r.match_id, r.competition, r.event_datetime, x.equipo, x.gana
    FROM r
    CROSS JOIN LATERAL (VALUES (r.home_team, r.home_score > r.away_score),
                               (r.away_team, r.away_score > r.home_score)) AS x(equipo, gana)
    WHERE r.home_score <> r.away_score
),
eq2 AS (
    SELECT eq.*,
           ROW_NUMBER() OVER (PARTITION BY competition, equipo ORDER BY event_datetime)
         - ROW_NUMBER() OVER (PARTITION BY competition, equipo, gana ORDER BY event_datetime) AS grupo,
           COALESCE(SUM(gana::int) OVER w, 0) AS ganados_antes,
           COUNT(*) OVER w AS jugados_antes,
           LAG(event_datetime) OVER (PARTITION BY competition, equipo ORDER BY event_datetime) AS anterior
    FROM eq
    WINDOW w AS (PARTITION BY competition, equipo ORDER BY event_datetime
                 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
),
eq3 AS (
    SELECT eq2.*,
           CASE WHEN gana THEN ROW_NUMBER() OVER (PARTITION BY competition, equipo, gana, grupo
                                                  ORDER BY event_datetime) END AS seguidas
    FROM eq2
),
eq4 AS (
    SELECT eq3.*, LAG(seguidas) OVER (PARTITION BY competition, equipo ORDER BY event_datetime) AS seguidas_antes
    FROM eq3
),
equipos AS (
    SELECT match_id, 40 AS orden, 'racha de victorias' AS tipo,
           equipo || ' suma ' || seguidas || ' victorias seguidas' AS detalle,
           CASE WHEN seguidas >= 12 THEN 3 WHEN seguidas >= 10 THEN 2 ELSE 1 END AS nivel
    FROM eq4
    WHERE gana AND (seguidas IN (8, 10, 12, 15, 20, 25) OR (seguidas > 25 AND seguidas % 5 = 0))
    UNION ALL
    SELECT match_id, 41, 'racha cortada',
           equipo || ' perdió y cortó una racha de ' || seguidas_antes || ' victorias seguidas',
           CASE WHEN seguidas_antes >= 12 THEN 3 WHEN seguidas_antes >= 10 THEN 2 ELSE 1 END
    FROM eq4
    WHERE NOT gana AND seguidas_antes >= 8
),
sorpresa AS (
    SELECT g.match_id, 42 AS orden, 'sorpresa' AS tipo,
           g.equipo || ' (' || g.ganados_antes || '-' || (g.jugados_antes - g.ganados_antes)
           || ') ganó a ' || p.equipo || ' (' || p.ganados_antes || '-'
           || (p.jugados_antes - p.ganados_antes) || ')' AS detalle,
           CASE WHEN dif >= 0.60 THEN 3 WHEN dif >= 0.50 THEN 2 ELSE 1 END AS nivel
    FROM eq2 g
    JOIN eq2 p ON p.match_id = g.match_id AND p.equipo <> g.equipo
    CROSS JOIN LATERAL (SELECT p.ganados_antes::numeric / p.jugados_antes
                             - g.ganados_antes::numeric / g.jugados_antes AS dif) d
    WHERE g.gana AND g.jugados_antes >= 6 AND p.jugados_antes >= 6 AND d.dif >= 0.40
),
back_to_back AS (
    SELECT e.match_id, 43 AS orden, 'back-to-back' AS tipo,
           e.equipo || ' ganó por ' || ABS(r.home_score - r.away_score)
           || ' jugando por segundo día seguido' AS detalle,
           1 AS nivel
    FROM eq2 e
    JOIN r USING (match_id)
    WHERE e.competition = 'nba' AND e.gana
      AND e.event_datetime - e.anterior < interval '30 hours'
      AND ABS(r.home_score - r.away_score) >= 15
),
todas AS (
    SELECT match_id, orden, tipo, detalle, nivel FROM remontada WHERE deficit >= 15
    UNION ALL SELECT * FROM racha
    UNION ALL SELECT * FROM ultima
    UNION ALL SELECT * FROM igualdad
    UNION ALL SELECT * FROM principio_fin
    UNION ALL SELECT * FROM paliza
    UNION ALL SELECT * FROM cuarto_record
    UNION ALL SELECT * FROM parcial_cuarto
    UNION ALL SELECT * FROM cuarto_blanco
    UNION ALL SELECT * FROM extremos
    UNION ALL SELECT * FROM prorroga
    UNION ALL SELECT * FROM gano_perdiendo
    UNION ALL SELECT * FROM jugadores
    UNION ALL SELECT * FROM mejor_marca
    UNION ALL SELECT * FROM doble_turno
    UNION ALL SELECT * FROM equipos
    UNION ALL SELECT * FROM sorpresa
    UNION ALL SELECT * FROM back_to_back
)
SELECT to_char(r.fecha, 'DD/MM/YYYY') AS fecha,
       t.nivel,
       r.competition AS liga,
       r.home_team || ' ' || r.home_score || '-' || r.away_score || ' ' || r.away_team AS partido,
       t.tipo,
       t.detalle,
       r.match_id
FROM todas t
JOIN r USING (match_id)
WHERE r.fecha BETWEEN :'desde'::date AND :'hasta'::date
  AND (:'liga' = '' OR r.competition = :'liga')
  AND t.nivel >= :nivel
ORDER BY r.event_datetime DESC, r.match_id, t.nivel DESC, t.orden, t.detalle;
