BEGIN;

CREATE TEMP TABLE target_match_ids (match_id varchar(255) PRIMARY KEY) ON COMMIT DROP;
INSERT INTO target_match_ids (match_id)
SELECT match_id FROM results.results WHERE event_datetime IS NULL
UNION
SELECT 'h81tlrkd';

DELETE FROM point_by_point.point_by_point_event WHERE match_id IN (SELECT match_id FROM target_match_ids);
DELETE FROM stats_player.stats_player WHERE match_id IN (SELECT match_id FROM target_match_ids);
DELETE FROM team_stats.team_stats WHERE match_id IN (SELECT match_id FROM target_match_ids);
DELETE FROM match_summary.match_summary WHERE match_id IN (SELECT match_id FROM target_match_ids);
DELETE FROM fixtures.fixtures WHERE match_id IN (SELECT match_id FROM target_match_ids);
DELETE FROM results.results WHERE match_id IN (SELECT match_id FROM target_match_ids);

COMMIT;
