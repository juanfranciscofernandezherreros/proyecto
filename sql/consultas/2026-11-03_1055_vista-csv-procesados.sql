-- =============================================================================
-- VISTA public.v_csv_procesados: CADA CSV IMPORTADO CON SU PARTIDO Y SU LIGA
-- =============================================================================
-- Fecha:     2026-11-03 10:55
-- Tipo:      ESCRITURA (crea o reemplaza una vista; no copia ni modifica datos)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1055_vista-csv-procesados.sql
--
-- PARA QUÉ SIRVE
--   El launcher registra cada CSV que importa en public.batch_launch_request, pero solo con
--   la ruta del fichero, el tipo de batch y su estado. Esta vista añade lo que hace falta
--   para entenderlo de un vistazo, y la usa el dashboard de Grafana "Basketball - CSV procesados":
--     · fichero     nombre del CSV sin la carpeta
--     · dataset     tipo legible (RESULTS, MATCH_SUMMARY, POINT_BY_POINT, TEAM_STATS, PLAYER_STATS, FIXTURES)
--     · match_id    sacado de la ruta ...\current\<match_id>\... (CSV de un partido); vacío
--                   en los CSV de competición (RESULTS / FIXTURES de una liga entera)
--     · liga        país/competición: del partido (results o fixtures) o, en los CSV de
--                   competición, de la ruta ...\competitions\<pais>\<competicion>\...
--     · partido     "Local - Visitante" cuando se conoce el partido
--     · segundos    duración de la importación
--
-- CUÁNDO USARLA
--   · Cada vez que se quiera saber qué CSV se ha importado, de qué partido y cómo fue.
--   · Si se cambia el formato de las rutas de los CSV, hay que revisar las expresiones
--     regulares de match_id y liga.
--
-- QUÉ TOCA Y QUÉ PROTEGE
--   Solo crea (o reemplaza) la vista. No toca ninguna tabla. Es repetible: volver a
--   ejecutarlo deja la vista igual.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  "CREATE VIEW" indica que la vista quedó creada.
--   PASO 2  muestra los 10 CSV más recientes: deben salir con liga y, si son de un partido,
--           con match_id y partido.
--   PASO 3  cuántos CSV quedan sin liga (debería ser 0 o casi).
--
-- RESULTADO EL 2026-11-03
--   CREATE VIEW. Los CSV recientes salen con liga y partido (p. ej. Dijon - Strasbourg, LNB).
--   496 CSV sin liga: son importaciones antiguas cuyas rutas no siguen ninguno de los dos
--   formatos (ni ...\current\<match_id>\ ni ...\competitions\<pais>\<competicion>\).
--   No afectan al dashboard, que lista los procesados en las últimas 24 h.
-- =============================================================================


-- PASO 1 · Crear (o reemplazar) la vista.
CREATE OR REPLACE VIEW public.v_csv_procesados AS
WITH csv AS (
    SELECT b.request_id, b.file_path, b.batch_type, b.status, b.attempts,
           b.created_at, b.started_at, b.finished_at, b.exit_code, b.error,
           regexp_replace(b.file_path, '^.*[/\\]', '')                                   AS fichero,
           substring(b.file_path FROM '[/\\]current[/\\]([A-Za-z0-9]+)[/\\]')            AS match_id,
           substring(b.file_path FROM 'competitions[/\\]([a-z0-9-]+)[/\\][a-z0-9-]+')    AS pais_ruta,
           substring(b.file_path FROM 'competitions[/\\][a-z0-9-]+[/\\]([a-z0-9-]+)')    AS competicion_ruta
    FROM public.batch_launch_request b
)
SELECT c.request_id,
       c.fichero,
       CASE c.batch_type
           WHEN 'results'        THEN 'RESULTS'
           WHEN 'match-summary'  THEN 'MATCH_SUMMARY'
           WHEN 'point-by-point' THEN 'POINT_BY_POINT'
           WHEN 'team-stats'     THEN 'TEAM_STATS'
           WHEN 'stats-player'   THEN 'PLAYER_STATS'
           WHEN 'fixtures'       THEN 'FIXTURES'
           ELSE upper(c.batch_type)
       END                                                                     AS dataset,
       c.status                                                                AS estado,
       c.match_id,
       coalesce(r.country || '/' || r.competition,
                f.country || '/' || f.competition,
                c.pais_ruta || '/' || c.competicion_ruta)                      AS liga,
       coalesce(r.home_team || ' - ' || r.away_team,
                f.home_team || ' - ' || f.away_team)                           AS partido,
       c.created_at                                                            AS encolado,
       c.started_at                                                            AS empezado,
       c.finished_at                                                           AS terminado,
       round(extract(epoch FROM c.finished_at - c.started_at))::int           AS segundos,
       c.attempts                                                              AS intentos,
       c.exit_code,
       c.error,
       c.file_path                                                             AS ruta
FROM csv c
LEFT JOIN results.results   r ON r.match_id = c.match_id
LEFT JOIN fixtures.fixtures f ON f.match_id = c.match_id AND r.match_id IS NULL;


-- PASO 2 · Comprobación: los 10 CSV más recientes.
SELECT encolado, dataset, estado, liga, match_id, partido, segundos, fichero
FROM public.v_csv_procesados
ORDER BY encolado DESC
LIMIT 10;


-- PASO 3 · CSV que se quedan sin liga (no se pudo deducir de la ruta ni del partido).
SELECT count(*) AS sin_liga
FROM public.v_csv_procesados
WHERE liga IS NULL;
