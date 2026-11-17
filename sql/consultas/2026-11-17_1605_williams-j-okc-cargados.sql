-- =============================================================================
-- COMPROBAR QUE LOS DOS "WILLIAMS J." DE OKC ENTRAN COMO JUGADORES DISTINTOS
-- =============================================================================
-- Fecha:     2026-11-17 16:05
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1605_williams-j-okc-cargados.sql
--
-- PARA QUÉ SIRVE   Tras la migración V2 (player_id) y recargar PLAYER_STATS con player_url,
--                  los partidos de OKC deben tener dos filas "Williams J." con distinto
--                  player_id (4G5tbqUi = Jalen, jD1xaPEo = Jaylin), y ninguna fila sin id.
-- CUÁNDO USARLA    Tras recargar h81tlrkd, l40Wzzzi o zFyE2s4k.
-- CÓMO LEER EL RESULTADO  PASO 1: una fila por jugador repetido y partido. PASO 2: filas
--                  sin player_id por partido; debe dar 0 en los partidos recargados.
-- QUÉ HACER DESPUÉS       Si falta un partido, recargarlo; si sale con filas sin id, revisar
--                  que el CSV cargado traía player_url.
-- RESULTADO EL 2026-11-17  (se completa tras ejecutarla)
-- =============================================================================

-- PASO 1 · Los "Williams J." de cada partido afectado, con su id y sus puntos.
SELECT match_id, name, team, player_id, pts, min
FROM stats_player.stats_player
WHERE match_id IN ('h81tlrkd', 'l40Wzzzi', 'zFyE2s4k') AND name = 'Williams J.'
ORDER BY match_id, pts DESC;

-- PASO 2 · Jugadores por partido y cuántos quedan sin player_id.
SELECT match_id, count(*) AS jugadores, count(*) FILTER (WHERE player_id IS NULL) AS sin_id
FROM stats_player.stats_player
WHERE match_id IN ('h81tlrkd', 'l40Wzzzi', 'zFyE2s4k')
GROUP BY match_id ORDER BY match_id;
