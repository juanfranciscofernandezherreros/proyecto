-- =============================================================================
-- TABLA public.pipeline_step: CADA PASO DEL ORQUESTADOR DE LIGAS (EXTRAER / IMPORTAR)
-- =============================================================================
-- Fecha:     2026-11-03 16:25
-- Tipo:      ESCRITURA (crea la tabla si no existe; no toca datos existentes)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1625_esquema-pipeline-step.sql
--
-- PARA QUÉ SIRVE
--   public.batch_launch_request solo registra la IMPORTACIÓN de un CSV ya generado. Mientras
--   Python extrae de Flashscore (que puede tardar horas por liga) no existe ningún CSV, y el
--   dashboard "Basketball - Procesamiento en vivo" parecía parado. Esta tabla la rellena
--   scripts\ligas\ORQUESTAR_LIGAS.ps1: una fila por paso (p. ej. "RESULTS extraer" de
--   LEGA_A) que se inserta en estado RUNNING al empezar y se cierra con OK / FALLO / OMITIDO.
--   Columnas: run_id (una ejecución del orquestador), liga (código de LIGAS_BASKET.json),
--   pais, competicion, paso, estado, intentos, started_at, finished_at, detalle (error).
--
-- CUÁNDO USARLA
--   La aplica el propio orquestador al arrancar (es repetible). Ejecutarla a mano solo si se
--   borra la tabla o se quiere crear antes de la primera ejecución.
--
-- QUÉ TOCA Y QUÉ PROTEGE
--   CREATE TABLE / INDEX IF NOT EXISTS: si ya existe, no cambia nada ni borra filas.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1-2  "CREATE TABLE"/"CREATE INDEX" o un NOTICE de que ya existía: ambos son correctos.
--   PASO 3    los últimos pasos registrados; estado RUNNING = se está haciendo ahora.
--
-- QUÉ HACER DESPUÉS
--   Si hay filas RUNNING muy antiguas, el orquestador se cortó sin cerrarlas (ventana cerrada,
--   reinicio). El dashboard solo trata como "en curso" las RUNNING de las últimas 12 h.
--
-- RESULTADO EL 2026-11-03
--   Tabla e índice creados; 0 filas (se rellena en la siguiente ejecución del orquestador).
-- =============================================================================


-- PASO 1 · Crear la tabla de pasos del orquestador.
CREATE TABLE IF NOT EXISTS public.pipeline_step (
    id          bigserial PRIMARY KEY,
    run_id      text        NOT NULL,
    liga        text        NOT NULL,
    pais        text,
    competicion text,
    paso        text        NOT NULL,
    estado      text        NOT NULL,
    intentos    int         NOT NULL DEFAULT 0,
    started_at  timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    detalle     text
);

-- PASO 2 · Índice para las consultas del dashboard (por fecha de inicio).
CREATE INDEX IF NOT EXISTS pipeline_step_started_idx ON public.pipeline_step (started_at DESC);

-- PASO 3 · Comprobar: últimos pasos registrados.
SELECT id, liga, paso, estado, started_at, finished_at FROM public.pipeline_step ORDER BY id DESC LIMIT 10;
