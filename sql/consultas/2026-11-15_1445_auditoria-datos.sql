-- =============================================================================
-- AUDITORÍA DE DATOS: QUÉ ESTÁ MAL AHORA MISMO EN POSTGRES
-- =============================================================================
-- Fecha:     2026-11-15 14:45
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_1445_auditoria-datos.sql
--
-- PARA QUÉ SIRVE
--   Reúne en una sola pasada los controles de integridad que antes estaban repartidos
--   en varias consultas de esta carpeta. Mira las tablas fuente del pipeline
--   (fixtures.fixtures, results.results, team_stats, stats_player, point_by_point,
--   dataset_unavailable y batch_launch_request) y cuenta las filas que rompen cada
--   regla. Es la consulta que ejecuta la skill `auditar-datos`.
--
-- CUÁNDO USARLA
--   · Después de una extracción o de procesar pendientes, para ver si dejó datos malos.
--   · Antes de dar por bueno un cambio en el scraper, los batches o el projector.
--   · Cuando en la web faltan partidos o salen mal y no se sabe por dónde empezar.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  una fila por control. `afectados` = 0 es lo bueno. `gravedad`:
--             ALTA   el partido no sale en la web o sale con datos falsos.
--             MEDIA  el partido sale, pero incompleto o mal clasificado.
--             INFO   no es un error por sí solo; sirve para medir.
--   PASOS 2–7  desglose de los controles que más se repiten, para saber a qué liga o
--           a qué partidos afecta. Si su control está a 0, no devuelven filas.
--
-- QUÉ HACER DESPUÉS (por control)
--   01 results_duplicados / 02 fixtures_duplicadas   no debería pasar (match_id es clave);
--        revisar el batch de importación.
--   03 results_sin_hora          backfill: 2026-11-07_1830_results-sin-event-time-no-salen-en-web.sql
--   04 results_sin_pais_o_competicion   reextraer RESULTS de la liga (skill extraer-resultados).
--   05 results_sin_fecha         igual que 04.
--   06 results_fecha_futura      2026-11-04_0900_results-fecha-futura-ano-mal.sql
--   07 results_empate            marcador mal leído; reextraer el partido.
--   08 results_parciales_no_suman   igual que 07.
--   09 fixtures_jugadas_sin_result   skill extraer-resultados / resultados-todas-las-ligas.
--   10 slug_distinto_fixture_result  2026-11-08_0000_normalizar-competiciones-fixtures.sql y
--        docs\PLAN-normalizacion-competiciones.md.
--   11 results_sin_fixture       INFO: se clasifican solo por el propio result.
--   12–14 results_sin_<dataset>  skill procesar-pendientes o extraer-datos-partido.
--   15 team_stats_metrica_invalida   2026-11-04_1135_team-stats-duplicadas-tras-reextraer.sql
--   16 stats_player_duplicados   reimportar PLAYER_STATS del partido.
--   17 cargas_fallidas_7_dias    mirar el error (PASO 7) y reenviar el CSV
--        (skill procesar-csv-resultados o procesar-pendientes).
--   18 team_stats_rebotes_en_scoring   rebotes guardados con categoría 'Scoring' (scraper
--        antiguo; el corregido usa 'Rebounds'). basket reextraer --dataset equipo <match_id>:
--        desde el 2026-11-15 el batch borra solo las filas antiguas al reimportar.
--   19 team_stats_tiro_sin_porcentaje  métrica de tiro (acaba en " %") con etiqueta válida
--        pero cuyo valor no lleva "%" (p. ej. "(8/16)"): fila descuadrada que el control 15
--        no ve. Mismo arreglo que el 18.
--   Los controles 15, 18 y 19 son tres caras del mismo problema: se arreglan a la vez
--   reextrayendo el partido. El PASO 6 da los partidos afectados por liga.
--
-- RESULTADO EL 2026-11-15
--   A cero: 01–08, 10 y 16 (sin duplicados, sin results sin hora/país/fecha, sin
--   fechas futuras, sin empates, parciales cuadran, slugs coinciden).
--   09 fixtures_jugadas_sin_result = 30 (9 ligas, todos del 14 y 15 de noviembre:
--      falta la extracción de RESULTS de la última jornada).
--   11 results_sin_fixture = 452 (INFO).
--   12/13/14 sin jugadas / stats equipo / stats jugadores = 24 / 24 / 25
--      (NBA 23–24 y super-lig 1).
--   15 team_stats_metrica_invalida = 7480 filas en 262 partidos (euroleague 88,
--      nba 57, bbl 55, lnb 44...): restos del scraper antiguo sin limpiar.
--   17 cargas_fallidas_7_dias = 1 (stats-player de h81tlrkd, 15 intentos).
-- =============================================================================

-- PASO 1 · Resumen: una fila por control con el número de filas o partidos afectados.
--   Cada bloque del UNION es un control independiente; el orden es el del número.
--   Los controles 12–14 solo cuentan partidos con más de 1 día (para dar tiempo a
--   procesarlos) y que no estén registrados como "no publicado por la fuente".
--   El control 15 detecta filas cuya métrica es en realidad un valor ("51.4%",
--   "(38/72)"): un número seguido de % o de /. Así no depende de una lista cerrada
--   de etiquetas (hay ligas con "Technical fouls") ni confunde las etiquetas que
--   empiezan por dígito ("2-point field goal %").
WITH jugados AS (
  SELECT r.match_id
  FROM results.results r
  WHERE r.event_datetime < now() - interval '1 day'
)
SELECT '01 results_duplicados' AS control, 'ALTA' AS gravedad,
       (SELECT count(*) FROM (SELECT 1 FROM results.results GROUP BY match_id HAVING count(*) > 1) d) AS afectados
UNION ALL
SELECT '02 fixtures_duplicadas', 'ALTA',
       (SELECT count(*) FROM (SELECT 1 FROM fixtures.fixtures GROUP BY match_id HAVING count(*) > 1) d)
UNION ALL
SELECT '03 results_sin_hora', 'ALTA',
       (SELECT count(*) FROM results.results WHERE event_time IS NULL OR event_time = '')
UNION ALL
SELECT '04 results_sin_pais_o_competicion', 'MEDIA',
       (SELECT count(*) FROM results.results
        WHERE country IS NULL OR country = '' OR competition IS NULL OR competition = '')
UNION ALL
SELECT '05 results_sin_fecha', 'MEDIA',
       (SELECT count(*) FROM results.results WHERE event_datetime IS NULL)
UNION ALL
SELECT '06 results_fecha_futura', 'ALTA',
       (SELECT count(*) FROM results.results WHERE event_datetime > now())
UNION ALL
SELECT '07 results_empate', 'ALTA',
       (SELECT count(*) FROM results.results WHERE home_score = away_score)
UNION ALL
SELECT '08 results_parciales_no_suman', 'MEDIA',
       (SELECT count(*) FROM results.results
        WHERE home_score1 IS NOT NULL AND away_score1 IS NOT NULL
          AND (home_score <> home_score1 + coalesce(home_score2,0) + coalesce(home_score3,0)
                             + coalesce(home_score4,0) + coalesce(home_score5,0)
            OR away_score <> away_score1 + coalesce(away_score2,0) + coalesce(away_score3,0)
                             + coalesce(away_score4,0) + coalesce(away_score5,0)))
UNION ALL
SELECT '09 fixtures_jugadas_sin_result', 'ALTA',
       (SELECT count(*) FROM fixtures.fixtures f
        WHERE f.event_datetime < now() - interval '3 hours'
          AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id))
UNION ALL
SELECT '10 slug_distinto_fixture_result', 'MEDIA',
       (SELECT count(*) FROM fixtures.fixtures f
        JOIN results.results r USING (match_id)
        WHERE coalesce(r.country,'') <> '' AND coalesce(r.competition,'') <> ''
          AND (f.country <> r.country OR f.competition <> r.competition))
UNION ALL
SELECT '11 results_sin_fixture', 'INFO',
       (SELECT count(*) FROM results.results r
        WHERE NOT EXISTS (SELECT 1 FROM fixtures.fixtures f WHERE f.match_id = r.match_id))
UNION ALL
SELECT '12 results_sin_jugadas', 'MEDIA',
       (SELECT count(*) FROM jugados j
        WHERE NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = j.match_id)
          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                          WHERE u.match_id = j.match_id AND u.dataset = 'POINT_BY_POINT'))
UNION ALL
SELECT '13 results_sin_stats_equipo', 'MEDIA',
       (SELECT count(*) FROM jugados j
        WHERE NOT EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = j.match_id)
          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                          WHERE u.match_id = j.match_id AND u.dataset = 'TEAM_STATS'))
UNION ALL
SELECT '14 results_sin_stats_jugadores', 'MEDIA',
       (SELECT count(*) FROM jugados j
        WHERE NOT EXISTS (SELECT 1 FROM stats_player.stats_player s WHERE s.match_id = j.match_id)
          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                          WHERE u.match_id = j.match_id AND u.dataset = 'PLAYER_STATS'))
UNION ALL
SELECT '15 team_stats_metrica_invalida', 'MEDIA',
       (SELECT count(*) FROM team_stats.team_stats WHERE metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]')
UNION ALL
SELECT '16 stats_player_duplicados', 'MEDIA',
       (SELECT count(*) FROM (SELECT 1 FROM stats_player.stats_player
                              GROUP BY match_id, team, name HAVING count(*) > 1) d)
UNION ALL
SELECT '17 cargas_fallidas_7_dias', 'MEDIA',
       (SELECT count(*) FROM public.batch_launch_request
        WHERE created_at > now() - interval '7 days'
          AND (status <> 'COMPLETED' OR coalesce(exit_code, 0) <> 0))
UNION ALL
SELECT '18 team_stats_rebotes_en_scoring', 'MEDIA',
       (SELECT count(*) FROM team_stats.team_stats
        WHERE category = 'Scoring'
          AND metric IN ('Offensive rebounds', 'Defensive rebounds', 'Total rebounds'))
UNION ALL
SELECT '19 team_stats_tiro_sin_porcentaje', 'MEDIA',
       (SELECT count(*) FROM team_stats.team_stats
        WHERE metric ~ ' %$'
          AND (home_value !~ '%' OR away_value !~ '%'))
ORDER BY control;

-- PASO 2 · Desglose por liga de los controles sobre results (03, 04, 06, 07 y 08).
--   Solo salen las ligas con algún problema. Sirve para saber qué liga reextraer.
SELECT coalesce(nullif(country,''),'(vacío)')      AS country,
       coalesce(nullif(competition,''),'(vacío)')  AS competition,
       count(*) FILTER (WHERE event_time IS NULL OR event_time = '')  AS sin_hora,
       count(*) FILTER (WHERE country IS NULL OR country = ''
                           OR competition IS NULL OR competition = '') AS sin_pais_comp,
       count(*) FILTER (WHERE event_datetime > now())                 AS fecha_futura,
       count(*) FILTER (WHERE home_score = away_score)                AS empate,
       count(*) FILTER (WHERE home_score1 IS NOT NULL AND away_score1 IS NOT NULL
         AND (home_score <> home_score1 + coalesce(home_score2,0) + coalesce(home_score3,0)
                            + coalesce(home_score4,0) + coalesce(home_score5,0)
           OR away_score <> away_score1 + coalesce(away_score2,0) + coalesce(away_score3,0)
                            + coalesce(away_score4,0) + coalesce(away_score5,0))) AS parciales_no_suman
FROM results.results
GROUP BY 1, 2
HAVING count(*) FILTER (WHERE event_time IS NULL OR event_time = '') > 0
    OR count(*) FILTER (WHERE country IS NULL OR country = ''
                           OR competition IS NULL OR competition = '') > 0
    OR count(*) FILTER (WHERE event_datetime > now()) > 0
    OR count(*) FILTER (WHERE home_score = away_score) > 0
    OR count(*) FILTER (WHERE home_score1 IS NOT NULL AND away_score1 IS NOT NULL
         AND (home_score <> home_score1 + coalesce(home_score2,0) + coalesce(home_score3,0)
                            + coalesce(home_score4,0) + coalesce(home_score5,0)
           OR away_score <> away_score1 + coalesce(away_score2,0) + coalesce(away_score3,0)
                            + coalesce(away_score4,0) + coalesce(away_score5,0))) > 0
ORDER BY 1, 2;

-- PASO 3 · Desglose del control 09: partidos jugados sin resultado, por liga.
SELECT f.country, f.competition,
       count(*)                                                 AS sin_resultado,
       min(f.event_datetime AT TIME ZONE 'Europe/Madrid')::date AS mas_antiguo,
       max(f.event_datetime AT TIME ZONE 'Europe/Madrid')::date AS mas_reciente
FROM fixtures.fixtures f
WHERE f.event_datetime < now() - interval '3 hours'
  AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id)
GROUP BY f.country, f.competition
ORDER BY sin_resultado DESC, f.country, f.competition;

-- PASO 4 · Desglose del control 10: pares de slugs que no coinciden entre el
--   calendario y el resultado del mismo partido (p. ej. acb / liga-endesa).
SELECT f.country AS fixture_country, f.competition AS fixture_competition,
       r.country AS result_country,  r.competition AS result_competition,
       count(*)  AS partidos
FROM fixtures.fixtures f
JOIN results.results r USING (match_id)
WHERE coalesce(r.country,'') <> '' AND coalesce(r.competition,'') <> ''
  AND (f.country <> r.country OR f.competition <> r.competition)
GROUP BY 1, 2, 3, 4
ORDER BY partidos DESC;

-- PASO 5 · Desglose de los controles 12–14: partidos jugados (hace más de 1 día) a los
--   que falta algún dataset de detalle sin estar marcado como no publicado, por liga.
SELECT coalesce(nullif(r.country,''),'(vacío)')     AS country,
       coalesce(nullif(r.competition,''),'(vacío)') AS competition,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = r.match_id)
                          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                                          WHERE u.match_id = r.match_id AND u.dataset = 'POINT_BY_POINT')) AS sin_jugadas,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = r.match_id)
                          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                                          WHERE u.match_id = r.match_id AND u.dataset = 'TEAM_STATS'))     AS sin_stats_equipo,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM stats_player.stats_player s WHERE s.match_id = r.match_id)
                          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                                          WHERE u.match_id = r.match_id AND u.dataset = 'PLAYER_STATS'))   AS sin_stats_jugadores,
       count(*) AS partidos_jugados
FROM results.results r
WHERE r.event_datetime < now() - interval '1 day'
GROUP BY 1, 2
HAVING count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = r.match_id)
                          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                                          WHERE u.match_id = r.match_id AND u.dataset = 'POINT_BY_POINT')) > 0
    OR count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = r.match_id)
                          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                                          WHERE u.match_id = r.match_id AND u.dataset = 'TEAM_STATS')) > 0
    OR count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM stats_player.stats_player s WHERE s.match_id = r.match_id)
                          AND NOT EXISTS (SELECT 1 FROM fixtures_processing_audit.dataset_unavailable u
                                          WHERE u.match_id = r.match_id AND u.dataset = 'PLAYER_STATS')) > 0
ORDER BY 1, 2;

-- PASO 6 · Desglose del control 15: partidos con filas de team_stats descuadradas,
--   por liga (la liga sale del result; "(sin result)" si el partido no lo tiene).
SELECT coalesce(nullif(r.country,''),'(sin result)')     AS country,
       coalesce(nullif(r.competition,''),'(sin result)') AS competition,
       count(DISTINCT t.match_id) AS partidos,
       count(*)                   AS filas_descuadradas
FROM team_stats.team_stats t
LEFT JOIN results.results r USING (match_id)
WHERE t.metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]'
GROUP BY 1, 2
ORDER BY filas_descuadradas DESC;

-- PASO 7 · Desglose del control 17: cargas del launcher fallidas en los últimos 7 días,
--   con el principio del error (las 20 más recientes).
SELECT created_at AT TIME ZONE 'Europe/Madrid' AS creada, batch_type, status, exit_code,
       attempts, left(file_path, 90) AS fichero, left(error, 120) AS error
FROM public.batch_launch_request
WHERE created_at > now() - interval '7 days'
  AND (status <> 'COMPLETED' OR coalesce(exit_code, 0) <> 0)
ORDER BY created_at DESC
LIMIT 20;
