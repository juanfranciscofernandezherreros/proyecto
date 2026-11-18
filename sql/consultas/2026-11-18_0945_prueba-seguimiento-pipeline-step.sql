-- =============================================================================
-- PRUEBA DEL SEGUIMIENTO EN pipeline_step (y limpieza de la fila de prueba)
-- =============================================================================
-- Fecha:     2026-11-18 09:45
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-18_0945_prueba-seguimiento-pipeline-step.sql
--
-- PARA QUÉ SIRVE   scripts\py\seguimiento.py escribe una fila RUNNING por partido y
--                  dataset en public.pipeline_step y la cierra al acabar; el panel
--                  "Extrayendo ahora" del dashboard de pendientes la lee. Se probó con
--                  una fila run_id='prueba-seguimiento' (pasos 1 y 2, los generó el
--                  script); el paso 3 la borra para no ensuciar el panel.
-- CUÁNDO USARLA    Para comprobar a mano que el seguimiento escribe.
-- CÓMO LEER EL RESULTADO  paso 1 devuelve el id; paso 2 UPDATE 1; paso 3 DELETE 1.
-- QUÉ HACER DESPUÉS       Nada; el paso 4 debe dar 0.
-- RESULTADO EL 2026-11-18 id 374 creado y cerrado; borrado con el paso 3.
-- =============================================================================

-- PASO 1 · (lo ejecutó seguimiento.empezar) Fila RUNNING de prueba.
INSERT INTO public.pipeline_step (run_id, liga, pais, competicion, paso, estado) VALUES ('prueba-seguimiento', 'europe/euroleague', 'europe', 'euroleague', 'PRUEBA', 'RUNNING') RETURNING id;

-- PASO 2 · (lo ejecutó seguimiento.terminar) La cierra. Solo toca la fila de prueba.
UPDATE public.pipeline_step SET estado = 'COMPLETED', intentos = intentos + 1, finished_at = now(), detalle = 'prueba' WHERE run_id = 'prueba-seguimiento';

-- PASO 3 · Borra las filas de prueba (run_id exclusivo de esta prueba).
DELETE FROM public.pipeline_step WHERE run_id = 'prueba-seguimiento';

-- PASO 4 · Comprobación: debe dar 0.
SELECT count(*) FROM public.pipeline_step WHERE run_id = 'prueba-seguimiento';
