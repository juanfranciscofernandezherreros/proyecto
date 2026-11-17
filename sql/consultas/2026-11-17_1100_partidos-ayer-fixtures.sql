-- =============================================================================
-- PARTIDOS DE AYER EN FIXTURES (CALENDARIO DE FLASHSCORE)
-- =============================================================================
-- Fecha:     2026-11-17 11:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1100_partidos-ayer-fixtures.sql
--
-- PARA QUÉ SIRVE   fixtures.fixtures es el calendario que se extrae de Flashscore. Se
--                  listan los partidos del 16-nov (hora de Madrid) para compararlos con
--                  la colección matches de MongoDB (lo que enseña la web).
-- CUÁNDO USARLA    Para saber si la web tiene todos los partidos de un día.
-- CÓMO LEER EL RESULTADO  Una fila por partido; los match_id se buscan luego en Mongo.
-- QUÉ HACER DESPUÉS       Los que falten en Mongo: skill diagnosticar-partido.
-- RESULTADO EL 2026-11-17 8 partidos (NBA 5, Winner League 3). Los 8 están en Mongo con marcador
--                  y las 6 secciones; Mongo no tiene ningún otro partido de ese día.
-- =============================================================================

-- PASO 1 · Partidos del 16-nov según fixtures.
SELECT match_id, country, competition, home_team, away_team,
       (event_datetime AT TIME ZONE 'Europe/Madrid') AS hora_madrid
FROM fixtures.fixtures
WHERE (event_datetime AT TIME ZONE 'Europe/Madrid')::date = DATE '2026-11-16'
ORDER BY event_datetime;
