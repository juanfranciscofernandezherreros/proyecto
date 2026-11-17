-- =============================================================================
-- ¿POR QUÉ 15 PARTIDOS PROCESADOS NO TIENEN 'players' EN MONGO?
-- =============================================================================
-- Fecha:     2026-11-17 14:35
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1435_players-sin-publicar-pendientes.sql
--
-- PARA QUÉ SIRVE   tras `basket pendientes` (parado en el partido 42 de 97), la
--                  comprobación en Mongo dio 42 de 42 partidos, 27 con todas las
--                  secciones y 15 con FALTAN players. Esta consulta mira, para esos 15,
--                  si Flashscore no publica las estadísticas de jugadores
--                  (fixtures_processing_audit.dataset_unavailable) y si hay filas en
--                  stats_player.stats_player.
-- CUÁNDO USARLA    cuando la comprobación final de pendientes dé FALTAN <secciones>.
-- CÓMO LEER EL RESULTADO  estado NO_PUBLICADO / VACIO = la fuente no lo tiene (no es
--                  fallo); filas_players > 0 sin la sección en Mongo = fallo del projector;
--                  sin registro y 0 filas = fallo real de extracción.
-- QUÉ HACER DESPUÉS       fallo real → `basket reextraer --dataset PLAYER_STATS <match_id>`.
-- RESULTADO EL 2026-11-17 15 filas, las 15 NO_PUBLICADO PLAYER_STATS (3 intentos) y
--                  0 filas en stats_player: Flashscore no lo publica, no es fallo.
-- =============================================================================

-- PASO 1 · Para cada partido sin 'players': registro de no publicado y filas cargadas.
WITH ids(match_id) AS (VALUES
  ('8zdrsx7r'),('0ACHrkrm'),('hKHjJYOj'),('nwLeiry8'),('EPMmg46e'),('MyRKOf1T'),('8ArlEYR6'),
  ('YccVDPXN'),('fZrepb5C'),('jacEkgsh'),('6LnPPFGa'),('bP0MmXB4'),('6k4UoBtH'),('OIh0SPIP'),('EqZAAmrm'))
SELECT i.match_id,
       u.estado, u.dataset, left(u.reason, 60) AS motivo, u.attempts,
       (SELECT count(*) FROM stats_player.stats_player s WHERE s.match_id = i.match_id) AS filas_players
FROM ids i
LEFT JOIN fixtures_processing_audit.dataset_unavailable u
       ON u.match_id = i.match_id AND u.dataset ILIKE '%PLAYER%'
ORDER BY u.estado NULLS FIRST, i.match_id;
