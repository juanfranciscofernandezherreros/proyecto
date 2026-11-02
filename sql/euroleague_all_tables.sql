WITH
euroliga_fixtures AS (
    SELECT f.*
    FROM fixtures.fixtures AS f
    WHERE lower(f.country) = 'europa'
      AND lower(f.competition) = 'euroliga'
),
euroliga_results AS (
    SELECT r.*
    FROM results.results AS r
    WHERE lower(r.competition) LIKE '%euroleague%'
),
partidos AS (
    SELECT match_id FROM euroliga_fixtures
    UNION
    SELECT match_id FROM euroliga_results
),
fixtures_por_partido AS (
    SELECT
        f.match_id,
        count(*) AS filas,
        jsonb_agg(to_jsonb(f) ORDER BY f.event_datetime NULLS LAST) AS datos
    FROM euroliga_fixtures AS f
    GROUP BY f.match_id
),
results_por_partido AS (
    SELECT
        r.match_id,
        count(*) AS filas,
        jsonb_agg(to_jsonb(r) ORDER BY r.event_datetime NULLS LAST) AS datos
    FROM euroliga_results AS r
    GROUP BY r.match_id
),
team_stats_por_partido AS (
    SELECT
        s.match_id,
        count(*) AS filas,
        jsonb_agg(to_jsonb(s) ORDER BY s.category, s.metric, s.id) AS datos
    FROM team_stats.team_stats AS s
    JOIN partidos AS p USING (match_id)
    GROUP BY s.match_id
),
stats_player_por_partido AS (
    SELECT
        s.match_id,
        count(*) AS filas,
        jsonb_agg(to_jsonb(s) ORDER BY s.team, s.name, s.id) AS datos
    FROM stats_player.stats_player AS s
    JOIN partidos AS p USING (match_id)
    GROUP BY s.match_id
),
match_summary_por_partido AS (
    SELECT
        s.match_id,
        count(*) AS filas,
        jsonb_agg(to_jsonb(s) ORDER BY s.id) AS datos
    FROM match_summary.match_summary AS s
    JOIN partidos AS p USING (match_id)
    GROUP BY s.match_id
),
point_by_point_por_partido AS (
    SELECT
        s.match_id,
        count(*) AS filas,
        jsonb_agg(to_jsonb(s) ORDER BY s.quarter, s.sequence) AS datos
    FROM point_by_point.point_by_point_event AS s
    JOIN partidos AS p USING (match_id)
    GROUP BY s.match_id
)
SELECT
    p.match_id,
    COALESCE(
        NULLIF(r.datos -> 0 ->> 'event_datetime', '')::timestamptz,
        NULLIF(f.datos -> 0 ->> 'event_datetime', '')::timestamptz
    ) AS event_datetime,
    COALESCE(r.datos -> 0 ->> 'home_team', f.datos -> 0 ->> 'home_team') AS home_team,
    COALESCE(r.datos -> 0 ->> 'away_team', f.datos -> 0 ->> 'away_team') AS away_team,
    COALESCE(f.filas, 0) AS fixture_rows,
    COALESCE(f.datos, '[]'::jsonb) AS fixtures,
    COALESCE(r.filas, 0) AS result_rows,
    COALESCE(r.datos, '[]'::jsonb) AS results,
    COALESCE(ts.filas, 0) AS team_stats_rows,
    COALESCE(ts.datos, '[]'::jsonb) AS team_stats,
    COALESCE(sp.filas, 0) AS stats_player_rows,
    COALESCE(sp.datos, '[]'::jsonb) AS stats_player,
    COALESCE(ms.filas, 0) AS match_summary_rows,
    COALESCE(ms.datos, '[]'::jsonb) AS match_summary,
    COALESCE(pb.filas, 0) AS point_by_point_rows,
    COALESCE(pb.datos, '[]'::jsonb) AS point_by_point
FROM partidos AS p
LEFT JOIN fixtures_por_partido AS f USING (match_id)
LEFT JOIN results_por_partido AS r USING (match_id)
LEFT JOIN team_stats_por_partido AS ts USING (match_id)
LEFT JOIN stats_player_por_partido AS sp USING (match_id)
LEFT JOIN match_summary_por_partido AS ms USING (match_id)
LEFT JOIN point_by_point_por_partido AS pb USING (match_id)
ORDER BY event_datetime NULLS LAST, p.match_id;
