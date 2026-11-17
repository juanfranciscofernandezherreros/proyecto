-- =============================================================================
-- MATCH_ID DE FIXTURES DE UN DIA (los usa `basket datos-ayer`)
-- =============================================================================
-- Fecha:     2026-11-17 10:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1000_ids-fixtures-ayer.sql
--
-- PARA QUÉ SIRVE   Sacar los match_id de fixtures.fixtures cuyo día local (Madrid) es
--                  el indicado. `basket datos-ayer` lanza esta misma consulta (con
--                  ayer o con la fecha que se le pase) y le da los IDs a reextraer.
-- CUÁNDO USARLA    Para ver qué partidos tratará `basket datos-ayer` para un día.
-- CÓMO LEER EL RESULTADO  Un match_id por fila.
-- QUÉ HACER DESPUÉS       `basket datos-ayer [AAAA-MM-DD]`.
-- RESULTADO EL 2026-11-17 10:00   8 filas para 2026-11-16 (Israel 3, NBA 5).
-- =============================================================================

-- PASO 1 · match_id de los partidos del 2026-11-16 (cambiar la fecha si se quiere otro día).
SELECT f.match_id
FROM fixtures.fixtures f
WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = DATE '2026-11-16'
ORDER BY f.match_id;
