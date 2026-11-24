-- =============================================================================
-- ESTADO DEL H2H EN POSTGRES
-- =============================================================================
-- Fecha:     2026-11-24 10:10
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1010_h2h-estado.sql
--
-- PARA QUÉ SIRVE   Saber qué ha llegado a Postgres de los CSV H2H_*.csv (historial
--                  entre equipos de Flashscore) antes de llevarlo al projector, Mongo,
--                  la API y la web. En Mongo ningún partido tiene h2h.
-- CUÁNDO USARLA    Antes y después de cargar o proyectar H2H.
-- CÓMO LEER EL RESULTADO  Paso 1: tablas del schema h2h. Paso 2: filas y partidos
--                  distintos por tabla (columna match_id si existe).
-- QUÉ HACER DESPUÉS       Si hay filas: proyectarlas a Mongo. Si no: cargar los CSV.
-- RESULTADO EL 2026-11-24 · El schema h2h no existe: 0 tablas, 0 filas. Hay 394 CSV H2H_*.csv en C:data pero nada se carga.
-- =============================================================================

-- PASO 1 · Tablas y columnas del schema h2h.
SELECT table_name, string_agg(column_name, ', ' ORDER BY ordinal_position) AS columnas
FROM information_schema.columns
WHERE table_schema = 'h2h'
GROUP BY table_name
ORDER BY table_name;

-- PASO 2 · Filas y partidos distintos de cada tabla del schema h2h.
SELECT 'h2h.' || table_name AS tabla,
       (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM h2h.%I', table_name), false, true, '')))[1]::text::bigint AS filas
FROM information_schema.tables
WHERE table_schema = 'h2h'
ORDER BY table_name;
