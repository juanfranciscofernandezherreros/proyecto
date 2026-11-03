-- =============================================================================
-- VISTA public.v_csv_generados: TODOS LOS CSV GENERADOS, AUNQUE SE REPITAN, CON SU ESTADO
-- =============================================================================
-- Fecha:     2026-11-03 16:35
-- Tipo:      ESCRITURA (crea o reemplaza una vista; no copia ni modifica datos)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1635_vista-csv-generados.sql
--
-- PARA QUÉ SIRVE
--   public.batch_launch_request tiene UNA fila por CONTENIDO (request_id = csv-sha256-...):
--   si un CSV nuevo es idéntico a otro ya importado, el launcher reutiliza la fila y solo
--   cambia file_path. Así, los CSV repetidos (p. ej. RESULTS sin partidos nuevos) no dejan
--   rastro propio, y como después los ficheros se borran, se pierde que existieron.
--   public.csv_generated_file (la rellena el GeneratedCsvMonitor del launcher cada 5 s) tiene
--   UNA fila por FICHERO. Esta vista parte de ella y añade el estado de su importación,
--   buscando en batch_launch_request el fichero por su NOMBRE: los CSV de partido se
--   consolidan de C:\data\basketball\competitions\... a C:\data\basketball-ready\current\<match_id>\
--   con el mismo nombre, y es esa copia la que se envía al launcher.
--     · estado   status del launcher (COMPLETED, FAILED, RUNNING, QUEUED) o SIN ENVIAR si
--                ninguna petición apunta a ese fichero
--     · repetido sí = el launcher reutilizó una petición creada antes de que existiera el
--                fichero, es decir, el contenido era igual a uno ya importado (no hay datos nuevos)
--   Limitación: si después llega otro CSV con el mismo contenido, la petición pasa a apuntar a
--   ese otro fichero y el anterior queda como SIN ENVIAR aunque se importara.
--   Columnas: generado (cuando lo detectó el monitor), fichero, dataset, liga (pais/competicion),
--   pais, competicion, match_id, estado, repetido, request_id, tamano_bytes, ruta. La usa el
--   dashboard de Grafana "Basketball - CSV procesados".
--
-- CUÁNDO USARLA
--   Para saber qué CSV se han generado y si cada uno se procesó, aunque ya se hayan borrado.
--
-- QUÉ TOCA Y QUÉ PROTEGE
--   Solo crea (o reemplaza) la vista. No toca ninguna tabla. Es repetible.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  "CREATE VIEW".
--   PASO 2  recuento por estado en la última hora: COMPLETED es bueno (con repetido = sí, no
--           traía datos nuevos); FAILED, o SIN ENVIAR durante más de unos minutos, indica que
--           algo no se importó.
--   PASO 3  los 15 CSV más recientes.
--
-- QUÉ HACER DESPUÉS
--   Si hay SIN ENVIAR antiguos, mirar el informe C:\data\basketball\reports\<pais>\<competicion>\
--   o relanzar con 1_EJECUTAR\MATCHIDS_PENDIENTES.bat.
--
-- RESULTADO EL 2026-11-03
--   CREATE VIEW. 138 CSV procesados hoy. En la última hora: los 11 RESULTS COMPLETED (con
--   repetido = sí, sin partidos nuevos); 12 POINT_BY_POINT/PLAYER_STATS SIN ENVIAR, que son
--   CSV vacíos (solo cabecera, 191 y 99 bytes: Flashscore aún no tenía datos) y nunca se
--   importan; 17 MATCH_DETAILS SIN ENVIAR (ese dataset no se envía al launcher).
-- =============================================================================


-- PASO 1 · Crear (o reemplazar) la vista. Se borra antes porque cambian sus columnas.
DROP VIEW IF EXISTS public.v_csv_generados;
CREATE VIEW public.v_csv_generados AS
SELECT g.discovered_at                                              AS generado,
       g.file_name                                                  AS fichero,
       CASE g.dataset
           WHEN 'results'        THEN 'RESULTS'
           WHEN 'match-summary'  THEN 'MATCH_SUMMARY'
           WHEN 'point-by-point' THEN 'POINT_BY_POINT'
           WHEN 'team-stats'     THEN 'TEAM_STATS'
           WHEN 'stats-player'   THEN 'PLAYER_STATS'
           WHEN 'fixtures'       THEN 'FIXTURES'
           ELSE upper(g.dataset)
       END                                                          AS dataset,
       g.country || '/' || g.competition                            AS liga,
       g.country                                                    AS pais,
       g.competition                                                AS competicion,
       g.match_id,
       coalesce(b.status, 'SIN ENVIAR')                             AS estado,
       CASE WHEN b.created_at < g.modified_at - interval '1 minute' THEN 'sí'
            WHEN b.request_id IS NOT NULL THEN 'no' END             AS repetido,
       b.request_id,
       g.size_bytes                                                 AS tamano_bytes,
       g.file_path                                                  AS ruta
FROM public.csv_generated_file g
LEFT JOIN LATERAL (
    SELECT r.request_id, r.status, r.created_at
    FROM public.batch_launch_request r
    WHERE r.file_path = g.file_path
       OR regexp_replace(r.file_path, '^.*\\', '') = g.file_name
    ORDER BY (r.file_path = g.file_path) DESC, r.created_at DESC
    LIMIT 1
) b ON true;

-- PASO 2 · Recuento por estado en la última hora.
SELECT dataset, estado, count(*) FROM public.v_csv_generados
WHERE generado > now() - interval '1 hour' GROUP BY 1, 2 ORDER BY 1, 2;

-- PASO 3 · Los 15 CSV más recientes.
SELECT generado AT TIME ZONE 'Europe/Madrid' AS generado, fichero, liga, estado
FROM public.v_csv_generados ORDER BY generado DESC LIMIT 15;
