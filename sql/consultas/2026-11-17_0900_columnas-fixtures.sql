-- =============================================================================
-- COLUMNAS DE LA TABLA FIXTURES
-- =============================================================================
-- Fecha:     2026-11-17 09:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_0900_columnas-fixtures.sql
--
-- PARA QUÉ SIRVE   ver qué columnas tiene fixtures (partidos programados) antes de
--                  consultar qué partidos de ayer ya se han jugado.
-- CUÁNDO USARLA    al montar consultas sobre fixtures y no conocer su estructura.
-- CÓMO LEER EL RESULTADO  una fila por columna: nombre, tipo y si admite nulos.
-- QUÉ HACER DESPUÉS       usar esos nombres en la consulta de partidos de ayer.
-- RESULTADO EL <fecha>    (pendiente de ejecutar)
-- =============================================================================

-- PASO 1 · Listar columnas y tipos de todas las tablas llamadas fixtures.
SELECT table_schema, table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'fixtures'
ORDER BY table_schema, ordinal_position;
