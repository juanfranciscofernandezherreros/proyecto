-- =============================================================================
-- ESQUEMA monitoring PARA EL TABLERO DE CONSUMO
-- =============================================================================
-- Fecha:     2026-11-03 12:00
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1200_esquema-monitoring-consumo.sql
--
-- PARA QUÉ SIRVE
--   Crea las tablas donde scripts\monitor\RECOLECTAR_CONSUMO.ps1 guarda cada pocos
--   segundos lo que consume el sistema, para que el dashboard de Grafana "Basketball -
--   Consumo" (uid consumo-recursos) lo dibuje con el datasource postgres-results:
--     monitoring.process_sample  CPU y RAM por componente (launcher, auditoría, scraper,
--                                Edge, Docker...) y de los contenedores de Docker.
--     monitoring.jvm_sample      heap de las JVM (leído con jcmd GC.heap_info).
--     monitoring.disk_sample     tamaño de %TEMP%, scoped_dir, target/, logs y datos.
--     monitoring.db_size_sample  tamaño de la base y de cada esquema, para ver el crecimiento.
--   El consumo actual de la base (conexiones, consultas) no se guarda: el dashboard lo
--   lee en directo de pg_stat_activity.
--
-- CUÁNDO USARLA
--   Una sola vez por base de datos (también tras recrear el contenedor de Postgres).
--   El recolector la ejecuta solo al arrancar; es idempotente (IF NOT EXISTS).
--
-- CÓMO LEER EL RESULTADO
--   psql responde CREATE SCHEMA / CREATE TABLE / CREATE INDEX, o un NOTICE "already
--   exists, skipping" si ya existían. El PASO 6 debe listar las cuatro tablas.
--
-- QUÉ HACER DESPUÉS
--   Arrancar el recolector:  scripts\arranque\ASEGURAR.bat consumo grafana
--   y abrir http://localhost:8084/d/consumo-recursos
--
-- RESULTADO EL 2026-11-03 12:05
--   Se creó el esquema y las cuatro tablas con sus índices; el PASO 6 devolvió
--   db_size_sample, disk_sample, jvm_sample, process_sample (4 filas).
-- =============================================================================

-- PASO 1 · Esquema propio, separado de los datos de negocio y de los batches.
--          No toca ninguna tabla existente.
CREATE SCHEMA IF NOT EXISTS monitoring;

-- PASO 2 · Muestras de CPU y RAM por proceso. cpu_pct es el % del total de la máquina
--          (100 = todos los núcleos al máximo). Solo inserta; IF NOT EXISTS protege
--          una tabla ya creada con datos.
CREATE TABLE IF NOT EXISTS monitoring.process_sample (
    sampled_at   timestamptz      NOT NULL,
    component    text             NOT NULL,
    process_name text             NOT NULL,
    pid          integer,
    cpu_pct      double precision,
    memory_mb    double precision NOT NULL,
    threads      integer
);
CREATE INDEX IF NOT EXISTS process_sample_time_idx ON monitoring.process_sample (sampled_at);

-- PASO 3 · Heap de cada JVM conocida (launcher, auditoría, batches).
CREATE TABLE IF NOT EXISTS monitoring.jvm_sample (
    sampled_at        timestamptz      NOT NULL,
    component         text             NOT NULL,
    pid               integer          NOT NULL,
    heap_used_mb      double precision,
    heap_committed_mb double precision
);
CREATE INDEX IF NOT EXISTS jvm_sample_time_idx ON monitoring.jvm_sample (sampled_at);

-- PASO 4 · Tamaño en disco de carpetas temporales y de datos.
CREATE TABLE IF NOT EXISTS monitoring.disk_sample (
    sampled_at timestamptz      NOT NULL,
    label      text             NOT NULL,
    path       text             NOT NULL,
    size_mb    double precision NOT NULL,
    files      integer
);
CREATE INDEX IF NOT EXISTS disk_sample_time_idx ON monitoring.disk_sample (sampled_at);

-- PASO 5 · Tamaño de la base y de cada esquema a lo largo del tiempo.
CREATE TABLE IF NOT EXISTS monitoring.db_size_sample (
    sampled_at  timestamptz      NOT NULL,
    schema_name text             NOT NULL,
    size_mb     double precision NOT NULL
);
CREATE INDEX IF NOT EXISTS db_size_sample_time_idx ON monitoring.db_size_sample (sampled_at);

-- PASO 6 · Comprobación (lectura): deben salir las cuatro tablas.
SELECT table_name FROM information_schema.tables WHERE table_schema = 'monitoring' ORDER BY 1;
