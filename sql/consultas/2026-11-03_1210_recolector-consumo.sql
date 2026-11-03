-- =============================================================================
-- CONSULTAS DEL RECOLECTOR DE CONSUMO (monitoring.*)
-- =============================================================================
-- Fecha:     2026-11-03 12:10
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1210_recolector-consumo.sql
--
-- PARA QUÉ SIRVE
--   Recoge el SQL que scripts\monitor\RECOLECTAR_CONSUMO.ps1 lanza de forma periódica,
--   para poder repetirlo a mano o entender de dónde salen los datos del dashboard
--   "Basketball - Consumo". Los INSERT de procesos, JVM y disco los genera el script
--   con valores medidos en Windows (no se pueden repetir desde SQL); aquí van las
--   consultas que sí son SQL puro: tamaño de la base, purga y comprobación.
--   Las tablas las crea 2026-11-03_1200_esquema-monitoring-consumo.sql.
--
-- CUÁNDO USARLA
--   Para tomar a mano una muestra del tamaño de la base, para purgar si las tablas
--   crecen demasiado, o para comprobar que el recolector está escribiendo.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1 inserta una fila "(total)" más una por esquema. PASO 2 borra las muestras
--   de más de 7 días (DELETE n). PASO 3: "ultima" debe tener menos de un minuto en
--   process_sample y jvm_sample, menos de 10 en disk_sample y menos de 5 en
--   db_size_sample; si es más antigua, el recolector está parado (mira
--   C:\data\basketball\reports\consumo\recolector-consumo.log).
--
-- QUÉ HACER DESPUÉS
--   Si el recolector está parado: scripts\arranque\ASEGURAR.bat consumo
--
-- RESULTADO EL 2026-11-03 12:20  (ver final del fichero)
-- =============================================================================

-- PASO 1 · Muestra del tamaño de la base y de cada esquema (cada 5 minutos en el script).
--          Solo inserta filas nuevas en monitoring.db_size_sample; no toca otras tablas.
INSERT INTO monitoring.db_size_sample (sampled_at, schema_name, size_mb)
SELECT now(), '(total)', pg_database_size(current_database()) / 1048576.0
UNION ALL
SELECT now(), n.nspname, sum(pg_total_relation_size(c.oid)) / 1048576.0
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'm', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname NOT LIKE 'pg_toast%'
GROUP BY n.nspname;

-- PASO 2 · Retención (cada hora en el script): borra solo muestras del esquema
--          monitoring con más de 7 días. Nunca toca datos de negocio ni de batches.
DELETE FROM monitoring.process_sample WHERE sampled_at < now() - interval '7 days';
DELETE FROM monitoring.jvm_sample     WHERE sampled_at < now() - interval '7 days';
DELETE FROM monitoring.disk_sample    WHERE sampled_at < now() - interval '7 days';
DELETE FROM monitoring.db_size_sample WHERE sampled_at < now() - interval '7 days';

-- PASO 3 · Comprobación (lectura): cuántas muestras hay y de cuándo es la última.
SELECT 'process_sample' AS tabla, count(*) AS filas, max(sampled_at) AS ultima FROM monitoring.process_sample
UNION ALL SELECT 'jvm_sample', count(*), max(sampled_at) FROM monitoring.jvm_sample
UNION ALL SELECT 'disk_sample', count(*), max(sampled_at) FROM monitoring.disk_sample
UNION ALL SELECT 'db_size_sample', count(*), max(sampled_at) FROM monitoring.db_size_sample;
