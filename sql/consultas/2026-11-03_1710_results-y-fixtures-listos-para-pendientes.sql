-- =============================================================================
-- ¿ESTÁN REGISTRADOS LOS ÚLTIMOS RESULTS Y FIXTURES? (ANTES DE SEGUIR CON PENDIENTES)
-- =============================================================================
-- Fecha:     2026-11-03 17:10
-- Tipo:      LECTURA
-- Ejecutar:  1_EJECUTAR\COMPROBAR_RESULTS_FIXTURES.bat
--            (o: docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1710_results-y-fixtures-listos-para-pendientes.sql)
--
-- PARA QUÉ SIRVE
--   MATCHIDS_PENDIENTES trabaja con la lista de la auditoría, que sale de cruzar fixtures
--   (calendario, fixtures.fixtures) con results (resultados, results.results). Si el último
--   RESULTS o FIXTURES de una liga no llegó a importarse, la auditoría trabaja con datos
--   viejos: faltan partidos recién jugados o se dan por pendientes partidos que no lo son.
--   Esta consulta da una línea por liga con:
--     · ultimo_results / estado_results   cuándo se generó el último CSV de RESULTS de esa liga
--                                         y qué pasó con él en el launcher (v_csv_generados)
--     · ultimo_fixtures / estado_fixtures lo mismo para FIXTURES
--     · ultimo_partido_con_resultado      fecha del partido más reciente en results.results
--     · jugados_sin_resultado             partidos del calendario ya jugados (hace más de 3 h)
--                                         que aún no están en results.results
--     · veredicto                         LISTO o el motivo para revisar
--
-- CUÁNDO USARLA
--   Después del paso de RESULTS del ciclo (LIGAS_ORQUESTAR ALL results) y antes de lanzar o
--   dejar seguir MATCHIDS_PENDIENTES.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  una línea por liga. veredicto:
--             LISTO                         RESULTS de hoy importado y sin huecos
--             RESULTS NO ES DE HOY          el último RESULTS de la liga es de otro día
--             RESULTS SIN IMPORTAR (estado) el último CSV no llegó a COMPLETED
--             N JUGADOS SIN RESULTADO       hay partidos del calendario ya jugados sin resultado
--           estado COMPLETED con "repetido = sí" es bueno: no había partidos nuevos.
--           FIXTURES solo se extrae de vez en cuando: un FIXTURES antiguo no bloquea.
--   PASO 2  resumen: ligas LISTO / a revisar. Si a_revisar = 0, se puede seguir con pendientes.
--
-- QUÉ HACER DESPUÉS
--   · RESULTS NO ES DE HOY o SIN IMPORTAR: relanzar esa liga con
--     1_EJECUTAR\LIGAS_ORQUESTAR.bat <CODIGO> results  y volver a ejecutar esta consulta.
--   · JUGADOS SIN RESULTADO: ver el detalle con scripts\pendientes\FIXTURES_SIN_RESULTS.bat
--     (suelen ser partidos aplazados o que Flashscore aún no ha cerrado).
--
-- RESULTADO EL 2026-11-03
--   11 ligas, 11 LISTO, a_revisar = 0. Todas con RESULTS de hoy (16:30-16:38) COMPLETED con
--   repetido = sí (sin partidos nuevos) y 0 jugados sin resultado. FIXTURES del 01/11; el de
--   serbia/superleague salió SIN ENVIAR. Quedan fixtures con nombres antiguos fuera del catálogo:
--   spain/acb (258) e israel/super-league (160), sin resultados.
-- =============================================================================


-- PASO 1 · Estado por liga.
WITH ligas AS (
    -- Las ligas del catálogo (LIGAS_BASKET.json) son las que tienen resultados. Así se dejan
    -- fuera restos con nombres antiguos que solo tienen fixtures (spain/acb, israel/super-league).
    SELECT DISTINCT country, competition FROM results.results WHERE country IS NOT NULL
), ultimo_csv AS (
    SELECT DISTINCT ON (pais, competicion, dataset) pais, competicion, dataset, generado, estado, repetido
    FROM public.v_csv_generados
    WHERE dataset IN ('RESULTS', 'FIXTURES')
    ORDER BY pais, competicion, dataset, generado DESC
), res AS (
    SELECT country, competition, max(event_datetime) AS ultimo
    FROM results.results GROUP BY 1, 2
), huecos AS (
    SELECT f.country, f.competition, count(*) AS n
    FROM fixtures.fixtures f
    WHERE f.event_datetime < now() - interval '3 hours'
      AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id)
    GROUP BY 1, 2
), t AS (
    SELECT l.country || '/' || l.competition                                   AS liga,
           r.generado                                                          AS ultimo_results,
           r.estado || coalesce(' (repetido ' || r.repetido || ')', '')        AS estado_results,
           f.generado                                                          AS ultimo_fixtures,
           f.estado                                                            AS estado_fixtures,
           res.ultimo                                                          AS ultimo_partido_con_resultado,
           coalesce(h.n, 0)                                                    AS jugados_sin_resultado,
           r.generado AS r_gen, r.estado AS r_estado
    FROM ligas l
    LEFT JOIN ultimo_csv r ON r.pais = l.country AND r.competicion = l.competition AND r.dataset = 'RESULTS'
    LEFT JOIN ultimo_csv f ON f.pais = l.country AND f.competicion = l.competition AND f.dataset = 'FIXTURES'
    LEFT JOIN res ON res.country = l.country AND res.competition = l.competition
    LEFT JOIN huecos h ON h.country = l.country AND h.competition = l.competition
)
SELECT liga,
       to_char(ultimo_results AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')    AS ultimo_results,
       estado_results,
       to_char(ultimo_fixtures AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI')   AS ultimo_fixtures,
       estado_fixtures,
       to_char(ultimo_partido_con_resultado AT TIME ZONE 'Europe/Madrid', 'DD/MM') AS ultimo_partido,
       jugados_sin_resultado,
       CASE
           WHEN r_gen IS NULL OR r_gen < date_trunc('day', now()) THEN 'RESULTS NO ES DE HOY'
           WHEN r_estado <> 'COMPLETED' THEN 'RESULTS SIN IMPORTAR (' || r_estado || ')'
           WHEN jugados_sin_resultado > 0 THEN jugados_sin_resultado || ' JUGADOS SIN RESULTADO'
           ELSE 'LISTO'
       END                                                                       AS veredicto
FROM t
ORDER BY (CASE WHEN r_gen IS NULL OR r_gen < date_trunc('day', now()) OR r_estado <> 'COMPLETED'
                 OR jugados_sin_resultado > 0 THEN 0 ELSE 1 END), liga;

-- PASO 2 · Resumen: si a_revisar = 0, todo está registrado y se puede seguir con pendientes.
WITH ultimo AS (
    SELECT DISTINCT ON (pais, competicion) pais, competicion, generado, estado
    FROM public.v_csv_generados WHERE dataset = 'RESULTS'
    ORDER BY pais, competicion, generado DESC
), ligas AS (
    -- Las ligas del catálogo (LIGAS_BASKET.json) son las que tienen resultados. Así se dejan
    -- fuera restos con nombres antiguos que solo tienen fixtures (spain/acb, israel/super-league).
    SELECT DISTINCT country, competition FROM results.results WHERE country IS NOT NULL
)
SELECT count(*) FILTER (WHERE u.generado >= date_trunc('day', now()) AND u.estado = 'COMPLETED'
                          AND NOT EXISTS (SELECT 1 FROM fixtures.fixtures f
                                          WHERE f.country = l.country AND f.competition = l.competition
                                            AND f.event_datetime < now() - interval '3 hours'
                                            AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id))) AS listas,
       count(*) AS ligas,
       count(*) - count(*) FILTER (WHERE u.generado >= date_trunc('day', now()) AND u.estado = 'COMPLETED'
                          AND NOT EXISTS (SELECT 1 FROM fixtures.fixtures f
                                          WHERE f.country = l.country AND f.competition = l.competition
                                            AND f.event_datetime < now() - interval '3 hours'
                                            AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id))) AS a_revisar
FROM ligas l
LEFT JOIN ultimo u ON u.pais = l.country AND u.competicion = l.competition;
