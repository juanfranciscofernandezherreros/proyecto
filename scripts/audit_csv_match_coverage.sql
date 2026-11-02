-- Run in basketball. All joins use local schemas.
DROP TABLE IF EXISTS audit_match_coverage;
CREATE TEMP TABLE audit_match_coverage AS
WITH expected AS (
    SELECT match_id
    FROM (SELECT DISTINCT match_id FROM results.results WHERE match_id IS NOT NULL) AS x
), fixtures AS (
    SELECT match_id, rows_count
    FROM (SELECT match_id, count(*) AS rows_count FROM fixtures.fixtures GROUP BY match_id) AS x
), team_stats AS (
    SELECT match_id, rows_count
    FROM (SELECT match_id, count(*) AS rows_count FROM team_stats.team_stats GROUP BY match_id) AS x
), match_stats AS (
    SELECT match_id, rows_count
    FROM (SELECT match_id, count(*) AS rows_count FROM match_summary.match_summary GROUP BY match_id) AS x
), player_stats AS (
    SELECT match_id, rows_count
    FROM (SELECT match_id, count(*) AS rows_count FROM stats_player.stats_player GROUP BY match_id) AS x
), point_by_point AS (
    SELECT match_id, rows_count
    FROM (SELECT match_id, count(*) AS rows_count FROM point_by_point.point_by_point_event GROUP BY match_id) AS x
)
SELECT e.match_id,
       CASE WHEN f.match_id IS NULL THEN 'MISSING' ELSE 'OK' END AS fixtures,
       COALESCE(f.rows_count, 0) AS fixtures_rows,
       CASE WHEN t.match_id IS NULL THEN 'MISSING' ELSE 'OK' END AS team_stats,
       COALESCE(t.rows_count, 0) AS team_stats_rows,
       CASE WHEN m.match_id IS NULL THEN 'MISSING' ELSE 'OK' END AS match_summary,
       COALESCE(m.rows_count, 0) AS match_summary_rows,
       CASE WHEN p.match_id IS NULL THEN 'MISSING' ELSE 'OK' END AS player_stats,
       COALESCE(p.rows_count, 0) AS player_stats_rows,
       CASE WHEN b.match_id IS NULL THEN 'MISSING' ELSE 'OK' END AS point_by_point,
       COALESCE(b.rows_count, 0) AS point_by_point_rows
FROM expected e
LEFT JOIN fixtures f USING (match_id)
LEFT JOIN team_stats t USING (match_id)
LEFT JOIN match_stats m USING (match_id)
LEFT JOIN player_stats p USING (match_id)
LEFT JOIN point_by_point b USING (match_id)
ORDER BY e.match_id;

-- Matriz completa por partido.
SELECT * FROM audit_match_coverage;

-- Solo partidos con algún flujo ausente.
SELECT * FROM audit_match_coverage
WHERE 'MISSING' IN (fixtures, team_stats, match_summary, player_stats, point_by_point)
ORDER BY match_id;

-- Resumen de partidos completos e incompletos.
SELECT count(*) AS expected_matches,
       count(*) FILTER (WHERE fixtures = 'OK' AND team_stats = 'OK'
                         AND match_summary = 'OK' AND player_stats = 'OK'
                         AND point_by_point = 'OK') AS complete_matches,
       count(*) FILTER (WHERE fixtures = 'MISSING' OR team_stats = 'MISSING'
                         OR match_summary = 'MISSING' OR player_stats = 'MISSING'
                         OR point_by_point = 'MISSING') AS incomplete_matches
FROM audit_match_coverage;
