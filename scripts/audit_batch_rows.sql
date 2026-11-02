-- Auditoría de filas por fichero. Ejecutar contra la base basketball.
-- La comparación principal es: status=COMPLETED, exit_code=COMPLETED y read_count=write_count.
-- Guardar el primer resultado como snapshot BEFORE y repetirlo después del batch como AFTER.

\echo '=== SNAPSHOT ACTUAL DE TABLAS DE NEGOCIO ==='
SELECT 'fixtures' AS flow, count(*) AS total_rows, count(DISTINCT match_id) AS total_matches FROM fixtures.fixtures
UNION ALL SELECT 'results', count(*), count(DISTINCT match_id) FROM results.results
UNION ALL SELECT 'match_summary', count(*), count(DISTINCT match_id) FROM match_summary.match_summary
UNION ALL SELECT 'stats_player', count(*), count(DISTINCT match_id) FROM stats_player.stats_player
UNION ALL SELECT 'point_by_point', count(*), count(DISTINCT match_id) FROM point_by_point.point_by_point_event
UNION ALL SELECT 'team_stats', count(*), count(DISTINCT match_id) FROM team_stats.team_stats
ORDER BY flow;

\echo '=== FILAS LEÍDAS Y ESCRITAS POR FICHERO ==='
WITH executions AS (
    SELECT 'fixtures' AS flow, e.job_execution_id, e.status, e.exit_code, e.exit_message,
           p.parameter_value AS file_path
    FROM fixtures_batch.batch_job_execution e
    JOIN fixtures_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'file'
    UNION ALL
    SELECT 'results', e.job_execution_id, e.status, e.exit_code, e.exit_message, p.parameter_value
    FROM results_batch.batch_job_execution e
    JOIN results_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'file'
    UNION ALL
    SELECT 'match_summary', e.job_execution_id, e.status, e.exit_code, e.exit_message, p.parameter_value
    FROM stats_match_batch.batch_job_execution e
    JOIN stats_match_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'file'
    UNION ALL
    SELECT 'stats_player', e.job_execution_id, e.status, e.exit_code, e.exit_message, p.parameter_value
    FROM stats_player_batch.batch_job_execution e
    JOIN stats_player_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'file'
    UNION ALL
    SELECT 'point_by_point', e.job_execution_id, e.status, e.exit_code, e.exit_message, p.parameter_value
    FROM point_by_point_batch.batch_job_execution e
    JOIN point_by_point_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'file'
    UNION ALL
    SELECT 'team_stats', e.job_execution_id, e.status, e.exit_code, e.exit_message, p.parameter_value
    FROM team_stats_batch.batch_job_execution e
    JOIN team_stats_batch.batch_job_execution_params p USING (job_execution_id)
    WHERE p.parameter_name = 'file'
), steps AS (
    SELECT 'fixtures' AS flow, job_execution_id, read_count, write_count, filter_count, read_skip_count, write_skip_count
    FROM fixtures_batch.batch_step_execution
    UNION ALL SELECT 'results', job_execution_id, read_count, write_count, filter_count, read_skip_count, write_skip_count FROM results_batch.batch_step_execution
    UNION ALL SELECT 'match_summary', job_execution_id, read_count, write_count, filter_count, read_skip_count, write_skip_count FROM stats_match_batch.batch_step_execution
    UNION ALL SELECT 'stats_player', job_execution_id, read_count, write_count, filter_count, read_skip_count, write_skip_count FROM stats_player_batch.batch_step_execution
    UNION ALL SELECT 'point_by_point', job_execution_id, read_count, write_count, filter_count, read_skip_count, write_skip_count FROM point_by_point_batch.batch_step_execution
    UNION ALL SELECT 'team_stats', job_execution_id, read_count, write_count, filter_count, read_skip_count, write_skip_count FROM team_stats_batch.batch_step_execution
)
SELECT x.flow, x.file_path, x.status, x.exit_code,
       s.read_count AS csv_rows, s.write_count AS persisted_rows,
       s.filter_count, s.read_skip_count, s.write_skip_count,
       CASE WHEN x.status = 'COMPLETED' AND x.exit_code = 'COMPLETED'
                 AND s.read_count = s.write_count AND s.filter_count = 0
            THEN 'OK' ELSE 'CHECK' END AS audit_status,
       x.exit_message
FROM executions x
LEFT JOIN steps s USING (flow, job_execution_id)
ORDER BY x.file_path, x.job_execution_id;

\echo '=== RESUMEN DE FICHEROS ==='
WITH audit AS (
    SELECT * FROM (
        SELECT 'fixtures' AS flow, e.status, e.exit_code, s.read_count, s.write_count, s.filter_count
        FROM fixtures_batch.batch_job_execution e
        JOIN fixtures_batch.batch_step_execution s USING (job_execution_id)
        UNION ALL SELECT 'results', e.status, e.exit_code, s.read_count, s.write_count, s.filter_count
        FROM results_batch.batch_job_execution e JOIN results_batch.batch_step_execution s USING (job_execution_id)
        UNION ALL SELECT 'match_summary', e.status, e.exit_code, s.read_count, s.write_count, s.filter_count
        FROM stats_match_batch.batch_job_execution e JOIN stats_match_batch.batch_step_execution s USING (job_execution_id)
        UNION ALL SELECT 'stats_player', e.status, e.exit_code, s.read_count, s.write_count, s.filter_count
        FROM stats_player_batch.batch_job_execution e JOIN stats_player_batch.batch_step_execution s USING (job_execution_id)
        UNION ALL SELECT 'point_by_point', e.status, e.exit_code, s.read_count, s.write_count, s.filter_count
        FROM point_by_point_batch.batch_job_execution e JOIN point_by_point_batch.batch_step_execution s USING (job_execution_id)
        UNION ALL SELECT 'team_stats', e.status, e.exit_code, s.read_count, s.write_count, s.filter_count
        FROM team_stats_batch.batch_job_execution e JOIN team_stats_batch.batch_step_execution s USING (job_execution_id)
    ) q
)
SELECT flow, count(*) AS jobs,
       count(*) FILTER (WHERE status = 'COMPLETED' AND exit_code = 'COMPLETED'
                              AND read_count = write_count AND filter_count = 0) AS ok_jobs,
       count(*) FILTER (WHERE NOT (status = 'COMPLETED' AND exit_code = 'COMPLETED'
                              AND read_count = write_count AND filter_count = 0)) AS check_jobs,
       coalesce(sum(read_count), 0) AS csv_rows,
       coalesce(sum(write_count), 0) AS persisted_rows
FROM audit
GROUP BY flow ORDER BY flow;

-- Para la cobertura por partido, ejecutar aparte:
--   docker exec -i local-validation-postgres-1 psql -U test -d basketball < scripts/audit_csv_match_coverage.sql
