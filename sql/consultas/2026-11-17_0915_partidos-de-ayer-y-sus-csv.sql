-- =============================================================================
-- PARTIDOS DE AYER Y LOS CSV QUE LOS REGISTRAN
-- =============================================================================
-- Fecha:     2026-11-17 09:15
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_0915_partidos-de-ayer-y-sus-csv.sql
--
-- PARA QUÉ SIRVE   Ver qué partidos de ayer (event_datetime) hay en results.results y qué
--                  CSV de detalle (v_csv_generados, la vista del dashboard) tiene cada uno.
--                  Los RESULTS son por liga y su nombre lleva la fecha de EXTRACCIÓN (hoy),
--                  no la del partido.
-- CUÁNDO USARLA    Cuando no se encuentren en el dashboard los partidos de un día.
-- CÓMO LEER EL RESULTADO  Paso 1: un partido por fila, con marcador y número de CSV de detalle
--                  y cuántos de ellos están COMPLETED. csv_detalle = 0 → falta procesarlo.
-- QUÉ HACER DESPUÉS       Los que tengan 0, basket pendientes.
-- RESULTADO EL 2026-11-17 6 partidos (3 Israel, 3 NBA). b7yrmjMF y xGVLu8Ek (NBA) sin ningún CSV
--                  de detalle; los otros 4 con detalle parcial.
-- =============================================================================

-- PASO 1 · Partidos de ayer y sus CSV de detalle.
SELECT r.country || '/' || r.competition AS liga, r.match_id, r.home_team, r.home_score,
       r.away_score, r.away_team,
       count(v.fichero) AS csv_detalle,
       count(v.fichero) FILTER (WHERE v.estado = 'COMPLETED') AS completados
FROM results.results r
LEFT JOIN public.v_csv_generados v ON v.match_id = r.match_id
WHERE r.event_datetime::date = current_date - 1
GROUP BY 1,2,3,4,5,6 ORDER BY 1,2;
