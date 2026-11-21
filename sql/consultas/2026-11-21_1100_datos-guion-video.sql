-- =============================================================================
-- DATOS PARA EL GUION DE VÍDEO DE LA SEMANA: PARTIDOS, MÁXIMOS ANOTADORES Y CLASIFICACIÓN
-- =============================================================================
-- Fecha:     2026-11-21 11:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-21_1100_datos-guion-video.sql
--
-- PARA QUÉ SIRVE   Completa 2026-11-21_1000_curiosidades-cronologicas.sql con lo que hace
--                  falta para redactar un guion: cuántos partidos hubo cada día por liga,
--                  los mejores anotadores de la semana y la clasificación (victorias y
--                  derrotas de toda la temporada cargada) de las ligas con más partidos.
--                  La semana es del 14 al 20 de noviembre de 2026 (fechas de Madrid);
--                  para otra semana, cambiar las dos fechas del CTE `semana`.
-- CUÁNDO USARLA    Al preparar el guion de vídeo semanal.
-- CÓMO LEER EL RESULTADO
--   PASO 1  partidos por día y liga de la semana.
--   PASO 2  los 15 mejores anotadores de la semana (nombre + equipo; nulos = 0).
--   PASO 3  clasificación por competición: PJ, victorias, derrotas y diferencia de
--           puntos. Solo cuenta los partidos cargados, no es la tabla oficial. En la NBA solo
--           cuenta la liga regular (desde el 20/10/2026, la noche de inauguración): la base de
--           datos también trae la pretemporada (4-19 de octubre) y sin quitarla los Lakers
--           salían 15-6 en vez de 13-3 (ver 2026-11-21_1130_nba-lakers-partidos-cargados.sql).
--   PASO 4  mejores partidos de equipo de la semana por puntos totales.
-- QUÉ HACER DESPUÉS  Cruzarlo con la información de internet y redactar el guion.
-- RESULTADO EL 2026-11-21  (ver docs/guion-video-semana-2026-11-14_20.md)
-- =============================================================================

-- PASO 1 · Partidos por día y liga en la semana.
WITH semana AS (SELECT DATE '2026-11-14' AS desde, DATE '2026-11-20' AS hasta)
SELECT to_char((r.event_datetime AT TIME ZONE 'Europe/Madrid')::date, 'DD/MM') AS dia,
       r.competition AS liga, COUNT(*) AS partidos
FROM results.results r, semana s
WHERE (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date BETWEEN s.desde AND s.hasta
  AND r.home_score IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;

-- PASO 2 · Mejores anotadores de la semana.
WITH semana AS (SELECT DATE '2026-11-14' AS desde, DATE '2026-11-20' AS hasta)
SELECT s.name AS jugador, s.team AS equipo, r.competition AS liga,
       COUNT(*) AS partidos, SUM(COALESCE(s.pts, 0)) AS puntos,
       ROUND(AVG(COALESCE(s.pts, 0)), 1) AS media,
       MAX(COALESCE(s.pts, 0)) AS maximo
FROM stats_player.stats_player s
JOIN results.results r USING (match_id), semana w
WHERE (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date BETWEEN w.desde AND w.hasta
GROUP BY s.name, s.team, r.competition
ORDER BY maximo DESC, puntos DESC
LIMIT 15;

-- PASO 3 · Clasificación (solo partidos cargados) de toda la temporada, por competición.
WITH partidos AS (
    SELECT competition, home_team AS equipo, home_score AS pf, away_score AS pc,
           (home_score > away_score)::int AS gana
    FROM results.results
    WHERE home_score IS NOT NULL AND away_score IS NOT NULL
      AND (competition <> 'nba' OR (event_datetime AT TIME ZONE 'Europe/Madrid')::date >= DATE '2026-10-20')
    UNION ALL
    SELECT competition, away_team, away_score, home_score, (away_score > home_score)::int
    FROM results.results
    WHERE home_score IS NOT NULL AND away_score IS NOT NULL
      AND (competition <> 'nba' OR (event_datetime AT TIME ZONE 'Europe/Madrid')::date >= DATE '2026-10-20')
)
SELECT competition AS liga, equipo, COUNT(*) AS pj, SUM(gana) AS v, COUNT(*) - SUM(gana) AS d,
       SUM(pf) - SUM(pc) AS dif
FROM partidos
WHERE competition IN ('nba', 'euroleague', 'liga-endesa')
GROUP BY competition, equipo
HAVING COUNT(*) >= 3
ORDER BY competition, v DESC, dif DESC;

-- PASO 4 · Partidos con más puntos de la semana.
WITH semana AS (SELECT DATE '2026-11-14' AS desde, DATE '2026-11-20' AS hasta)
SELECT to_char((r.event_datetime AT TIME ZONE 'Europe/Madrid')::date, 'DD/MM') AS dia, r.competition AS liga,
       r.home_team || ' ' || r.home_score || '-' || r.away_score || ' ' || r.away_team AS partido,
       r.home_score + r.away_score AS total
FROM results.results r, semana s
WHERE (r.event_datetime AT TIME ZONE 'Europe/Madrid')::date BETWEEN s.desde AND s.hasta
  AND r.home_score IS NOT NULL
ORDER BY total DESC
LIMIT 8;
