-- =============================================================================
-- CURIOSIDADES DEL JUGADA A JUGADA: IGUALDAD, RACHAS, DE PRINCIPIO A FIN Y FINALES
-- =============================================================================
-- Fecha:     2026-11-20 23:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-20_2300_curiosidades-jugada-a-jugada.sql
--
-- PARA QUÉ SIRVE   Cuatro rankings sacados de point_by_point.point_by_point_event (una fila
--                  por canasta con el marcador tras ella), cruzado con results.results para
--                  el ganador y el marcador final. Complementa la consulta de remontadas
--                  (2026-11-20_1000_partidos-ganados-tras-gran-remontada.sql).
--                  Limitaciones: el jugada a jugada solo trae los cuartos 1 a 4 (sin
--                  prórrogas) y no trae el reloj, solo el orden de las canastas.
-- CUÁNDO USARLA    Para curiosidades/artículos o tras cargar jugadas nuevas.
-- CÓMO LEER EL RESULTADO
--   PASO 1  cambios_lider = veces que el líder pasó a ser el otro equipo (aunque fuera
--           pasando por un empate); empates = canastas que dejaron el marcador igualado.
--   PASO 2  racha = puntos seguidos de un equipo sin que el rival anotara (p. ej. 18-0);
--           marcador_antes / marcador_despues en orden local-visitante.
--   PASO 3  ganadores que nunca fueron por detrás; primero el recuento por competición y
--           después los 10 más ajustados al final.
--   PASO 4  partidos sin prórroga ganados con la última canasta: justo antes el ganador
--           iba empatado o perdiendo.
-- QUÉ HACER DESPUÉS  Un partido raro se revisa con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-20  PASO 1: máx. 26 cambios de líder (Cayirova-Bandirma y
--                  Rockets-Wolves, 12 empates). PASO 2: máx. 23-0 (Pistons ante Celtics en
--                  el 4º; Maccabi ante Galil Elyon en el 1º). PASO 3: de principio a fin del
--                  6 % (lega-a) al 25 % (superleague); el más ajustado, Braunschweig 83-82.
--                  PASO 4: 38 partidos ganados con la última canasta. PASO 5: 2643 jugadas
--                  de 882 partidos con *_points_added mal, todas en la 1ª jugada de un cuarto
--                  (guardan el marcador acumulado), y 140 saltos de más de 3 puntos.
-- =============================================================================

-- PASO 1 · Partidos más igualados: más cambios de líder y más empates.
WITH ev AS (
    SELECT match_id, quarter, sequence,
           SIGN(home_score - away_score) AS lider
    FROM point_by_point.point_by_point_event
),
con_lider AS (
    SELECT match_id, lider,
           LAG(lider) OVER (PARTITION BY match_id ORDER BY quarter, sequence) AS lider_previo
    FROM ev
    WHERE lider <> 0
),
cambios AS (
    SELECT match_id, COUNT(*) FILTER (WHERE lider <> lider_previo) AS cambios_lider
    FROM con_lider GROUP BY match_id
),
empates AS (
    SELECT match_id, COUNT(*) FILTER (WHERE lider = 0) AS empates FROM ev GROUP BY match_id
)
SELECT c.cambios_lider, e.empates,
       r.home_team || ' - ' || r.away_team AS partido,
       r.home_score || '-' || r.away_score AS final,
       r.competition, r.event_datetime::date AS fecha, r.match_id
FROM cambios c
JOIN empates e USING (match_id)
JOIN results.results r USING (match_id)
ORDER BY c.cambios_lider DESC, e.empates DESC, r.event_datetime DESC
LIMIT 15;

-- PASO 2 · Mayores rachas: más puntos seguidos de un equipo sin respuesta del rival.
--          OJO: no se usan home_points_added/away_points_added porque en la primera
--          jugada de algunos cuartos guardan el marcador acumulado (ver PASO 5). Los puntos
--          de cada canasta se calculan como diferencia con el marcador de la jugada anterior.
WITH ordenadas AS (
    SELECT match_id, quarter, sequence, home_score, away_score,
           ROW_NUMBER() OVER (PARTITION BY match_id ORDER BY quarter, sequence) AS n
    FROM point_by_point.point_by_point_event
),
deltas AS (
    SELECT *,
           home_score - COALESCE(LAG(home_score) OVER w, 0) AS dl,
           away_score - COALESCE(LAG(away_score) OVER w, 0) AS dv
    FROM ordenadas
    WINDOW w AS (PARTITION BY match_id ORDER BY n)
),
canastas AS (
    -- Solo canastas de un único equipo; si ambos suben a la vez (jugadas perdidas) la
    -- canasta queda fuera y corta la racha.
    SELECT match_id, quarter, n, home_score, away_score,
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
           MIN(quarter) AS desde_cuarto, MAX(quarter) AS hasta_cuarto,
           (ARRAY_AGG(home_score - CASE WHEN anota = 'home' THEN puntos ELSE 0 END ORDER BY m))[1] AS local_antes,
           (ARRAY_AGG(away_score - CASE WHEN anota = 'away' THEN puntos ELSE 0 END ORDER BY m))[1] AS visit_antes,
           (ARRAY_AGG(home_score ORDER BY m DESC))[1] AS local_despues,
           (ARRAY_AGG(away_score ORDER BY m DESC))[1] AS visit_despues,
           BOOL_AND(puntos BETWEEN 1 AND 3) AS limpia
    FROM islas
    GROUP BY match_id, anota, isla
)
SELECT ra.racha || '-0' AS parcial,
       CASE WHEN ra.anota = 'home' THEN r.home_team ELSE r.away_team END AS equipo,
       r.home_team || ' - ' || r.away_team AS partido,
       ra.local_antes || '-' || ra.visit_antes AS marcador_antes,
       ra.local_despues || '-' || ra.visit_despues AS marcador_despues,
       CASE WHEN ra.desde_cuarto = ra.hasta_cuarto THEN ra.desde_cuarto
            ELSE ra.desde_cuarto || ' a ' || ra.hasta_cuarto END AS cuando,
       r.home_score || '-' || r.away_score AS final,
       r.competition, r.event_datetime::date AS fecha, r.match_id
FROM rachas ra
JOIN results.results r USING (match_id)
WHERE ra.limpia   -- descarta rachas con saltos de más de 3 puntos (jugadas que faltan)
  AND ra.anota <> 'ambos'
ORDER BY ra.racha DESC, r.event_datetime DESC
LIMIT 15;

-- PASO 3 · Ganadores de principio a fin (nunca por detrás en el marcador).
--          3a: cuántos por competición. 3b: los 10 más ajustados al final.
WITH margen AS (
    SELECT p.match_id,
           MIN(CASE WHEN r.home_score > r.away_score THEN p.home_score - p.away_score
                    ELSE p.away_score - p.home_score END) AS peor_margen
    FROM point_by_point.point_by_point_event p
    JOIN results.results r USING (match_id)
    WHERE r.home_score <> r.away_score
    GROUP BY p.match_id
)
SELECT r.competition,
       COUNT(*) AS partidos_con_jugadas,
       COUNT(*) FILTER (WHERE m.peor_margen >= 0) AS de_principio_a_fin,
       ROUND(100.0 * COUNT(*) FILTER (WHERE m.peor_margen >= 0) / COUNT(*), 1) AS pct
FROM margen m JOIN results.results r USING (match_id)
GROUP BY r.competition
ORDER BY pct DESC;

WITH margen AS (
    SELECT p.match_id,
           MIN(CASE WHEN r.home_score > r.away_score THEN p.home_score - p.away_score
                    ELSE p.away_score - p.home_score END) AS peor_margen
    FROM point_by_point.point_by_point_event p
    JOIN results.results r USING (match_id)
    WHERE r.home_score <> r.away_score
    GROUP BY p.match_id
)
SELECT ABS(r.home_score - r.away_score) AS diferencia_final,
       CASE WHEN r.home_score > r.away_score THEN r.home_team ELSE r.away_team END AS ganador,
       r.home_team || ' - ' || r.away_team AS partido,
       r.home_score || '-' || r.away_score AS final,
       r.competition, r.event_datetime::date AS fecha, r.match_id
FROM margen m JOIN results.results r USING (match_id)
WHERE m.peor_margen >= 0
ORDER BY diferencia_final, r.event_datetime DESC
LIMIT 10;

-- PASO 4 · Ganados con la última canasta (sin prórroga, y el jugada a jugada acaba con el
--          mismo marcador que el resultado, para no fiarse de jugadas incompletas).
WITH ev AS (
    SELECT p.match_id, p.home_score, p.away_score,
           ROW_NUMBER() OVER (PARTITION BY p.match_id ORDER BY p.quarter DESC, p.sequence DESC) AS desde_final
    FROM point_by_point.point_by_point_event p
),
ultimas AS (
    SELECT match_id,
           MAX(home_score) FILTER (WHERE desde_final = 1) AS local_fin,
           MAX(away_score) FILTER (WHERE desde_final = 1) AS visit_fin,
           MAX(home_score) FILTER (WHERE desde_final = 2) AS local_antes,
           MAX(away_score) FILTER (WHERE desde_final = 2) AS visit_antes
    FROM ev WHERE desde_final <= 2
    GROUP BY match_id
)
SELECT CASE WHEN r.home_score > r.away_score THEN r.home_team ELSE r.away_team END AS ganador,
       u.local_antes || '-' || u.visit_antes AS antes_de_la_ultima,
       r.home_score || '-' || r.away_score AS final,
       r.home_team || ' - ' || r.away_team AS partido,
       r.competition, r.event_datetime::date AS fecha, r.match_id
FROM ultimas u
JOIN results.results r USING (match_id)
WHERE r.home_score5 IS NULL AND r.away_score5 IS NULL
  AND u.local_fin = r.home_score AND u.visit_fin = r.away_score
  AND CASE WHEN r.home_score > r.away_score THEN u.local_antes - u.visit_antes
           ELSE u.visit_antes - u.local_antes END <= 0
ORDER BY r.event_datetime DESC;

-- PASO 5 · Calidad del dato: jugadas cuyo *_points_added no cuadra con la diferencia de
--          marcador respecto a la jugada anterior (fallo de la extracción al empezar cuarto),
--          y saltos de marcador de más de 3 puntos (jugadas que faltan).
WITH d AS (
    SELECT match_id, quarter, sequence, home_points_added, away_points_added,
           home_score - COALESCE(LAG(home_score) OVER w, 0) AS dl,
           away_score - COALESCE(LAG(away_score) OVER w, 0) AS dv
    FROM point_by_point.point_by_point_event
    WINDOW w AS (PARTITION BY match_id ORDER BY quarter, sequence)
)
SELECT COUNT(*) AS jugadas,
       COUNT(*) FILTER (WHERE home_points_added <> dl OR away_points_added <> dv) AS points_added_mal,
       COUNT(DISTINCT match_id) FILTER (WHERE home_points_added <> dl OR away_points_added <> dv) AS partidos_afectados,
       COUNT(*) FILTER (WHERE sequence = 1 AND (home_points_added <> dl OR away_points_added <> dv)) AS de_ellas_en_primera_jugada,
       COUNT(*) FILTER (WHERE dl > 3 OR dv > 3 OR dl < 0 OR dv < 0) AS saltos_raros
FROM d;
