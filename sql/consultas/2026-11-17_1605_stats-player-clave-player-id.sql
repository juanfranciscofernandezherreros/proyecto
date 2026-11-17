-- =============================================================================
-- STATS_PLAYER: CLAVE CON EL ID DE JUGADOR (MIGRACIÓN V2 DEL BATCH)
-- =============================================================================
-- Fecha:     2026-11-17 16:05
-- Tipo:      ESCRITURA (DDL)
-- Ejecutar:  la aplica Flyway sola al arrancar el JAR csv-stats-player-batch (V2__player_id.sql);
--            este fichero es copia literal para dejar constancia. Comprobar con el PASO 2.
--
-- PARA QUÉ SIRVE   Jalen y Jaylin Williams (OKC) salen los dos como "Williams J." y chocaban
--                  en uk_stats_player_match_player_team (match_id, name, team): el lote de
--                  PLAYER_STATS fallaba entero. Se añade player_id (id de Flashscore) y
--                  player_key = COALESCE(player_id, name), y la unicidad pasa a
--                  (match_id, team, player_key).
-- CUÁNDO USARLA    Solo una vez (Flyway no la repite). Útil para entender el esquema.
-- CÓMO LEER EL RESULTADO  PASO 2: deben salir player_id, player_key y el índice nuevo; el
--                  constraint antiguo ya no debe existir.
-- QUÉ HACER DESPUÉS       Recargar los partidos afectados (basket reextraer <match_id>).
-- RESULTADO EL 2026-11-17  (se completa tras aplicarla)
-- Filas que toca: ninguna se modifica; player_key se calcula para las existentes (= name).
-- =============================================================================

-- PASO 1 · La migración, copia literal de V2__player_id.sql (schema stats_player).
-- Dos jugadores con el mismo nombre abreviado en un partido (Jalen y Jaylin Williams, los
-- dos "Williams J." en OKC) chocaban en la clave (match_id, name, team) y el lote entero
-- fallaba. La clave pasa a usar el id de Flashscore del jugador cuando el CSV lo trae.
ALTER TABLE stats_player ADD COLUMN IF NOT EXISTS player_id VARCHAR(64);

-- player_key: el id del jugador o, en filas antiguas sin id, su nombre.
ALTER TABLE stats_player ADD COLUMN IF NOT EXISTS player_key VARCHAR(255)
    GENERATED ALWAYS AS (COALESCE(player_id, name)) STORED;

ALTER TABLE stats_player DROP CONSTRAINT IF EXISTS uk_stats_player_match_player_team;
CREATE UNIQUE INDEX IF NOT EXISTS uk_stats_player_match_team_player
    ON stats_player (match_id, team, player_key);

-- PASO 2 · Comprobación: columnas nuevas e índices de stats_player.
SELECT column_name, data_type, is_generated
FROM information_schema.columns
WHERE table_schema = 'stats_player' AND table_name = 'stats_player' AND column_name IN ('player_id', 'player_key');
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'stats_player' AND tablename = 'stats_player';
