-- =============================================================================
-- REGISTRO DE DATASETS "SIN DATOS EN LA FUENTE" (corta el bucle de pendientes)
-- =============================================================================
-- Fecha:     2026-11-03 18:15
-- Tipo:      ESCRITURA (crea tabla y filas) + LECTURA (inspeccion)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1815_registro-datasets-sin-datos.sql
--
-- PARA QUE SIRVE
--   Flashscore no publica ciertos datasets para algunos partidos (p. ej. la LNB francesa:
--   point-by-point vacio, 0 eventos en los 4 cuartos). El extractor devolvia el CSV vacio,
--   el pipeline (process_pending_match_csvs.py) lanzaba RuntimeError, el partido quedaba
--   ERROR y la auditoria lo seguia viendo PENDIENTE: MATCHIDS_PENDIENTES lo reabria en cada
--   arranque para siempre (3 horas atascado en la liga francesa).
--   Corregido el 2026-11-03: cuando un dataset sale vacio tras 3 intentos, el pipeline hace
--   POST a la auditoria (/fixtures-processing-audit/dataset-unavailable) y la fila queda aqui.
--   La auditoria (AUDIT_SQL) ya NO cuenta como pendiente un dataset marcado aqui, asi que el
--   partido pasa a COMPLETO y el orquestador deja de reabrirlo. La tabla la crea el servicio
--   de auditoria de forma idempotente al arrancar (no usa Flyway porque es de solo lectura).
--
-- CUANDO USARLA
--   . Para ver que partidos/datasets se han marcado como SIN DATOS y por que.
--   . Para forzar un reintento de un partido: borrar su fila (PASO 3) y relanzar pendientes.
--
-- COMO LEER EL RESULTADO
--   PASO 1  definicion de la tabla (solo informativo; el servicio ya la crea).
--   PASO 2  filas actuales: match_id, dataset, razon, numero de intentos y cuando se vio.
--           attempts alto = la fuente lleva mucho sin publicarlo (casi seguro que no existe).
--   PASO 3  (ESCRITURA opcional) borrar una marca para volver a intentar ese dataset.
--
-- QUE HACER DESPUES
--   Tras el arreglo basta con relanzar MATCHIDS_PENDIENTES. Los partidos cuyo unico hueco
--   sea un dataset marcado aqui dejaran de salir pendientes.
--
-- RESULTADO EL 2026-11-03
--   LNB francesa atascada por point-by-point / player_stats vacios (WjMjs4C7, 6qDrG8Cs,
--   pYb38tB6, z1MCLUlK, E9GjEnsf, pUrHHLmn, t44G2Bvo...). Al marcarlos SIN DATOS dejan de
--   reabrirse.
-- =============================================================================

-- PASO 1 (LECTURA) . Estructura de la tabla del registro.
\d+ fixtures_processing_audit.dataset_unavailable

-- PASO 2 (LECTURA) . Datasets marcados como SIN DATOS, los mas reintentados primero.
--   estado VACIO        = la pagina existe pero tiene 0 filas.
--   estado NO_PUBLICADO = el bloque/enlace no existe en la fuente (p. ej. stats por cuartos).
SELECT match_id, country, competition, dataset, estado, rows_found, attempts, first_seen, last_seen, source_url
FROM fixtures_processing_audit.dataset_unavailable
ORDER BY attempts DESC, last_seen DESC;

-- PASO 2b (LECTURA) . Resumen por liga y dataset (lo mismo que muestra el dashboard
--   "Basketball - Datasets vacios / no publicados").
SELECT country, competition, dataset, estado, count(*) AS partidos
FROM fixtures_processing_audit.dataset_unavailable
GROUP BY country, competition, dataset, estado
ORDER BY partidos DESC;

-- PASO 3 (ESCRITURA opcional) . Forzar un reintento: borra la marca de UN partido+dataset.
--   Protege los demas registros con el filtro exacto por match_id y dataset. Descomenta y
--   ajusta antes de ejecutar; luego vuelve a lanzar pendientes para reintentar la extraccion.
-- DELETE FROM fixtures_processing_audit.dataset_unavailable
-- WHERE match_id = 'WjMjs4C7' AND dataset = 'POINT_BY_POINT';
