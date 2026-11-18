-- =============================================================================
-- QUÉ VE GRAFANA MIENTRAS SE EXTRAE DE FLASHSCORE
-- =============================================================================
-- Fecha:     2026-11-18 09:20
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-18_0920_grafana-extrayendo-ahora.sql
--
-- PARA QUÉ SIRVE   El dashboard "Procesamiento en vivo" cuenta "Extrayendo ahora" con
--                  public.pipeline_step (solo lo escribe ligas/orquestar.py) y "En curso"
--                  con public.batch_launch_request (importaciones del launcher). basket
--                  resultados-ayer / reextraer scrapea sin escribir en ninguna de las dos.
-- CUÁNDO USARLA    Cuando el dashboard no muestre nada pero haya extracción en marcha.
-- CÓMO LEER EL RESULTADO  paso 1 = pasos del orquestador en curso; paso 2 = últimas
--                  importaciones del launcher (solo aparecen al acabar cada CSV).
-- QUÉ HACER DESPUÉS       Si el paso 1 da 0 con reextraer en marcha, es la carencia del
--                  seguimiento: reextraer debería registrar sus pasos en pipeline_step.
-- RESULTADO EL 2026-11-18 paso 1: 0 (con reextraer scrapeando Minnesota). Paso 2: solo
--                  CncRmqpm y Gr62XNa6. Paso 3: los CSV NBA de hoy (09:00) aparecen con
--                  created_at del 17/11 17:xx: la fila del batch se reutiliza y conserva la fecha
--                  del primer intento, así que los paneles "de hoy" no los cuentan.
-- =============================================================================

-- PASO 1 · Pasos del orquestador en curso en las últimas 12 h (panel "Extrayendo ahora").
SELECT count(*) AS en_curso FROM public.pipeline_step
 WHERE estado = 'RUNNING' AND started_at > now() - interval '12 hours';

-- PASO 2 · Últimas importaciones del launcher hoy.
SELECT status, batch_type, regexp_replace(file_path, '^.*[/]', '') AS fichero, created_at
  FROM public.batch_launch_request
 WHERE created_at >= date_trunc('day', now())
 ORDER BY created_at DESC LIMIT 8;

-- PASO 3 · ¿Se importaron los CSV de la NBA extraídos hoy (ImtSeK4m, KM5gf7Tr, GQGF1ky9)?
SELECT status, batch_type, created_at, left(file_path, 120) AS fichero
  FROM public.batch_launch_request
 WHERE file_path LIKE '%ImtSeK4m%' OR file_path LIKE '%KM5gf7Tr%' OR file_path LIKE '%GQGF1ky9%'
 ORDER BY created_at DESC LIMIT 12;
