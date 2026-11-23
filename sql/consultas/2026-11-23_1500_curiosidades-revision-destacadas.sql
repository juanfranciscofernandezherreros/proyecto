-- =============================================================================
-- REVISIÓN A MANO DE LAS CURIOSIDADES MÁS DESTACADAS (NIVEL 3)
-- =============================================================================
-- Fecha:     2026-11-23 15:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-23_1500_curiosidades-revision-destacadas.sql
--
-- PARA QUÉ SIRVE   Comprobar contra las tablas de origen (sin la lógica de
--                  2026-11-23_1400_curiosidades-ampliadas.sql) cinco curiosidades de nivel 3
--                  antes de usarlas en un vídeo: la línea de Wembanyama (52-24), los 10
--                  triples de Grimes, el 48 en un cuarto de Cleveland, el 25-0 de Hapoel
--                  Jerusalem y el balance de Kings y Celtics antes del 22/11.
-- CUÁNDO USARLA    Tras cambiar la consulta de curiosidades o si un dato parece raro.
-- CÓMO LEER EL RESULTADO  Cada paso debe repetir la cifra del `detalle` de la curiosidad.
-- QUÉ HACER DESPUÉS       Si no cuadra, revisar el partido con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-23  Todo cuadra: Wembanyama 52 pts, 24 reb, 8 tapones, 1/8 en triples
--                  (Spurs 112-111 Mavericks); Grimes 47 pts, 10/14 en triples; Cleveland 48
--                  en el 2º cuarto en Milwaukee (48-21); Hapoel Jerusalem de 7-7 a 32-7 sin
--                  respuesta (25-0); Kings 1-14 y Celtics 11-4 antes del 22/11.
-- =============================================================================

-- PASO 1 · Línea de Wembanyama y de Grimes (stats_player tal cual).
SELECT s.name, s.team, s.pts, s.reb, s.bs, s.threepm, s.threepa, r.home_team, r.home_score, r.away_score, r.away_team
FROM stats_player.stats_player s JOIN results.results r USING (match_id)
WHERE (s.name = 'Wembanyama V.' AND s.pts >= 50) OR (s.name = 'Grimes Q.' AND s.threepm >= 10);

-- PASO 2 · Cuarto de 48 de Cleveland (parciales de results).
SELECT home_team, away_team, home_score1, home_score2, home_score3, home_score4,
       away_score1, away_score2, away_score3, away_score4, event_datetime
FROM results.results
WHERE competition = 'nba' AND 48 IN (home_score1, home_score2, home_score3, home_score4,
                                     away_score1, away_score2, away_score3, away_score4);

-- PASO 3 · El 25-0 de Hapoel Jerusalem: marcador jugada a jugada del 1º y 2º cuarto
--          entre 7-7 y 32-7.
SELECT p.quarter, p.sequence, p.home_score, p.away_score
FROM point_by_point.point_by_point_event p JOIN results.results r USING (match_id)
WHERE r.home_team = 'Hapoel Jerusalem' AND r.away_team = 'Maccabi Ashdod'
  AND p.home_score BETWEEN 7 AND 32 AND p.away_score = 7
ORDER BY p.quarter, p.sequence;

-- PASO 4 · Balance de Kings y Celtics en liga regular antes del partido del 22/11.
SELECT equipo, SUM(gana::int) AS ganados, COUNT(*) - SUM(gana::int) AS perdidos
FROM (SELECT x.equipo, x.gana
      FROM results.results r
      CROSS JOIN LATERAL (VALUES (r.home_team, r.home_score > r.away_score),
                                 (r.away_team, r.away_score > r.home_score)) AS x(equipo, gana)
      WHERE r.competition = 'nba' AND r.home_score IS NOT NULL
        AND r.event_datetime >= TIMESTAMPTZ '2026-10-19 22:00:00+00'
        AND (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date < DATE '2026-11-22') t
WHERE equipo IN ('Sacramento Kings', 'Boston Celtics')
GROUP BY equipo;
