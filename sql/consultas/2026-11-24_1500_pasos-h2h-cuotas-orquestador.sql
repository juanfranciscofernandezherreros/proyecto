-- =============================================================================
-- PASOS H2H+CUOTAS EN EL PANEL DEL ORQUESTADOR
-- =============================================================================
-- Fecha:     2026-11-24 15:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1500_pasos-h2h-cuotas-orquestador.sql
--
-- PARA QUÉ SIRVE   basket reextraer --dataset h2h-cuotas anota un paso «H2H+CUOTAS
--                  <match_id>» por partido en public.pipeline_step, que es lo que leen
--                  los paneles «Extrayendo ahora» y «Orquestador» de Grafana
--                  (Procesamiento en vivo). Comprueba que se están escribiendo.
-- CUÁNDO USARLA    Si el panel no muestra la extracción de H2H y cuotas.
-- CÓMO LEER EL RESULTADO  RUNNING = extrayendo ahora; COMPLETED con el resumen de los
--                  5 CSV; FAILED con «n con fallo».
-- QUÉ HACER DESPUÉS       Si no hay filas con lotes en marcha, revisar que el lote se
--                  lanzó con el reextraer.py de main (commit 1fe9075 o posterior).
-- RESULTADO EL 2026-11-24  Primero 0 filas (lotes aún arrancando); después
--                  RUNNING europe/euroleague «H2H+CUOTAS EZya2rat», visible en Grafana
--                  como «Extrayendo ahora 1».
-- =============================================================================

-- PASO 1 · Los últimos pasos H2H+CUOTAS.
SELECT estado, liga, paso, started_at, finished_at, detalle
FROM public.pipeline_step
WHERE paso LIKE 'H2H+CUOTAS%'
ORDER BY started_at DESC
LIMIT 10;
