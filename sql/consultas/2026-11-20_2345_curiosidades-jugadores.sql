-- =============================================================================
-- CURIOSIDADES DE JUGADORES: DOBLES-DOBLES, TRIPLES-DOBLES, RACHAS Y PARTIDOS DE 40
-- =============================================================================
-- Fecha:     2026-11-20 23:45
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-20_2345_curiosidades-jugadores.sql
--
-- PARA QUÉ SIRVE   Rankings de jugador sacados de stats_player.stats_player (una fila por
--                  jugador y partido), con results.results para la fecha y la competición.
--                  Las estadísticas vacías (NULL) cuentan como 0: Flashscore deja la
--                  casilla en blanco cuando el valor es 0.
--                  El jugador se identifica con player_key + team (player_key = player_id o,
--                  si falta, el nombre abreviado). Dos jugadores con el mismo nombre
--                  abreviado en el mismo equipo se mezclarían (PLAN-jugadores-con-nombre-repetido.md).
-- CUÁNDO USARLA    Para curiosidades/artículos o tras cargar estadísticas nuevas.
-- CÓMO LEER EL RESULTADO
--   PASO 1  dobles_dobles / triples_dobles = partidos con 10 o más en dos / tres de:
--           puntos, rebotes, asistencias, robos, tapones.
--   PASO 2  cada triple-doble, con su línea.
--   PASO 3  jugadores en racha: media de puntos de sus 5 últimos partidos frente a la de
--           toda la temporada (mínimo 8 partidos). dif > 0 = está mejor que su media.
--   PASO 4  partidos de 40 puntos o más.
-- QUÉ HACER DESPUÉS  La página de jugador de la web (/performances/<nombre>) da el detalle.
-- RESULTADO EL 2026-11-20  1: Towns 11 dobles-dobles; Jokic 4 triples-dobles. 2: 13
--                  triples-dobles, todos NBA. 3: Wembanyama +9,5 (35,2 en los 5 últimos).
--                  4: 30 partidos de 40+, todos NBA; máximo Doncic 53. Fuera de la NBA el
--                  máximo es 37 (euroleague, basket-league, winner-league).
-- =============================================================================

-- PASO 1 · Ranking de dobles-dobles y triples-dobles.
WITH lineas AS (
    SELECT s.player_key, s.name, s.team, s.match_id,
           (COALESCE(s.pts, 0) >= 10)::int + (COALESCE(s.reb, 0) >= 10)::int
         + (COALESCE(s.ast, 0) >= 10)::int + (COALESCE(s.st, 0) >= 10)::int
         + (COALESCE(s.bs, 0) >= 10)::int AS dobles
    FROM stats_player.stats_player s
)
SELECT name AS jugador, team AS equipo, COUNT(*) AS partidos,
       COUNT(*) FILTER (WHERE dobles >= 2) AS dobles_dobles,
       COUNT(*) FILTER (WHERE dobles >= 3) AS triples_dobles
FROM lineas
GROUP BY player_key, name, team
HAVING COUNT(*) FILTER (WHERE dobles >= 2) > 0
ORDER BY dobles_dobles DESC, triples_dobles DESC, partidos
LIMIT 15;

-- PASO 2 · Todos los triples-dobles.
SELECT s.name AS jugador, s.team AS equipo,
       COALESCE(s.pts, 0) AS pts, COALESCE(s.reb, 0) AS reb, COALESCE(s.ast, 0) AS ast,
       COALESCE(s.st, 0) AS rob, COALESCE(s.bs, 0) AS tap,
       r.home_team || ' ' || r.home_score || '-' || r.away_score || ' ' || r.away_team AS partido,
       r.competition, r.event_datetime::date AS fecha, s.match_id
FROM stats_player.stats_player s
LEFT JOIN results.results r USING (match_id)
WHERE (COALESCE(s.pts, 0) >= 10)::int + (COALESCE(s.reb, 0) >= 10)::int
    + (COALESCE(s.ast, 0) >= 10)::int + (COALESCE(s.st, 0) >= 10)::int
    + (COALESCE(s.bs, 0) >= 10)::int >= 3
ORDER BY r.event_datetime DESC;

-- PASO 3 · Jugadores en racha: últimos 5 partidos frente a la media de la temporada.
WITH partidos AS (
    SELECT s.player_key, s.name, s.team, COALESCE(s.pts, 0) AS pts, r.competition,
           ROW_NUMBER() OVER (PARTITION BY s.player_key, s.team ORDER BY r.event_datetime DESC) AS reciente
    FROM stats_player.stats_player s
    JOIN results.results r USING (match_id)
    WHERE r.event_datetime IS NOT NULL
)
SELECT name AS jugador, team AS equipo, MAX(competition) AS competicion,
       COUNT(*) AS partidos,
       ROUND(AVG(pts), 1) AS media_temporada,
       ROUND(AVG(pts) FILTER (WHERE reciente <= 5), 1) AS media_ultimos_5,
       ROUND(AVG(pts) FILTER (WHERE reciente <= 5) - AVG(pts), 1) AS dif
FROM partidos
GROUP BY player_key, name, team
HAVING COUNT(*) >= 8
ORDER BY dif DESC
LIMIT 15;

-- PASO 4 · Partidos de 40 puntos o más.
SELECT s.pts, s.name AS jugador, s.team AS equipo,
       COALESCE(s.reb, 0) AS reb, COALESCE(s.ast, 0) AS ast,
       COALESCE(s.threepm, 0) || '/' || COALESCE(s.threepa, 0) AS triples, s.min,
       r.home_team || ' ' || r.home_score || '-' || r.away_score || ' ' || r.away_team AS partido,
       r.competition, r.event_datetime::date AS fecha, s.match_id
FROM stats_player.stats_player s
LEFT JOIN results.results r USING (match_id)
WHERE s.pts >= 40
ORDER BY s.pts DESC, r.event_datetime DESC;
