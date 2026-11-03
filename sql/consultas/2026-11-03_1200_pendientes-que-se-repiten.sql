-- =============================================================================
-- POR QUÉ LOS PARTIDOS "YA PROCESADOS" VUELVEN A SALIR COMO PENDIENTES
-- =============================================================================
-- Fecha:     2026-11-03 12:00
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_1200_pendientes-que-se-repiten.sql
--
-- PARA QUÉ SIRVE
--   La auditoría (csv-extra-batch\fixtures-processing-audit) marca un partido jugado como
--   PENDIENTE si le falta CUALQUIERA de: results/match_summary, point_by_point,
--   team_stats o stats_player. No guarda intentos: si un dataset no existe en Flashscore
--   (liga sin play-by-play, por ejemplo), el partido sale pendiente en cada arranque y
--   MATCHIDS_PENDIENTES lo vuelve a abrir y a extraer, aunque el resto ya esté guardado.
--   Esta consulta mide cuántos partidos están en esa situación y qué les falta.
--
-- CUÁNDO USARLA
--   · Cuando el arranque o el ciclo diario procesen otra vez partidos que parecían hechos.
--   · Después de cambiar la auditoría, para comprobar que los "imposibles" ya no salen.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  por competición: jugados, completos, pendientes y cuántos tienen los datos
--           "parciales" (algo guardado pero falta algún dataset). Muchos parciales en una
--           liga = esa liga no publica algún dataset y se reintentará siempre.
--   PASO 2  combinaciones exactas de datasets que faltan. Si casi todo es "solo falta
--           point_by_point" (o similar), es un dataset que la fuente no da.
--
-- QUÉ HACER DESPUÉS
--   Ver el plan del 2026-11-03: registrar intentos fallidos y dejar de reintentar los
--   datasets que la fuente no publica.
--
-- RESULTADO EL 2026-11-03
--   397 pendientes. 365 sin NINGÚN dataset (NBA 102, Liga Endesa 48, Lega A 45, BSL 45,
--   LKL 38, Basket League 33, Winner 22...). 32 parciales (LNB 16, BBL 15): casi todos les
--   falta solo PLAYER_STATS (16) o POINT_BY_POINT (8). Euroliga y ACB, completas.
--   Los logs muestran el mismo match_id fallando en cada arranque (xjKmxuFk 16 veces,
--   WjMjs4C7 4 veces: point-by-point vacío en Flashscore, 0 eventos en los 4 cuartos).
-- =============================================================================

-- PASO 1 · Estado de cada partido jugado (antes de hoy) por competición, con la misma
--          regla que la auditoría (fixtures + results que no están en fixtures).
WITH m AS (
    SELECT f.match_id, f.country, f.competition, f.event_datetime FROM fixtures.fixtures f
    UNION ALL
    SELECT r.match_id, r.country, r.competition, r.event_datetime FROM results.results r
    WHERE NOT EXISTS (SELECT 1 FROM fixtures.fixtures f WHERE f.match_id = r.match_id)
), e AS (
    SELECT m.*,
           EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = m.match_id)                         AS res,
           EXISTS (SELECT 1 FROM match_summary.match_summary s WHERE s.match_id = m.match_id)             AS sumy,
           EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = m.match_id)     AS pbp,
           EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = m.match_id)                   AS ts,
           EXISTS (SELECT 1 FROM stats_player.stats_player sp WHERE sp.match_id = m.match_id)             AS ps
    FROM m
    WHERE (m.event_datetime AT TIME ZONE 'Europe/Madrid')::date < (now() AT TIME ZONE 'Europe/Madrid')::date
)
SELECT country, competition,
       count(*)                                                                   AS jugados,
       count(*) FILTER (WHERE res AND sumy AND pbp AND ts AND ps)                 AS completos,
       count(*) FILTER (WHERE NOT (res AND sumy AND pbp AND ts AND ps))           AS pendientes,
       count(*) FILTER (WHERE NOT (res AND sumy AND pbp AND ts AND ps)
                          AND (sumy OR pbp OR ts OR ps))                          AS parciales,
       count(*) FILTER (WHERE NOT pbp) AS sin_pbp, count(*) FILTER (WHERE NOT ts) AS sin_team,
       count(*) FILTER (WHERE NOT ps)  AS sin_player, count(*) FILTER (WHERE NOT sumy) AS sin_summary
FROM e GROUP BY country, competition ORDER BY pendientes DESC;

-- PASO 2 · Combinaciones exactas de lo que falta entre los pendientes.
WITH m AS (
    SELECT f.match_id, f.event_datetime FROM fixtures.fixtures f
    UNION ALL
    SELECT r.match_id, r.event_datetime FROM results.results r
    WHERE NOT EXISTS (SELECT 1 FROM fixtures.fixtures f WHERE f.match_id = r.match_id)
), e AS (
    SELECT concat_ws(',',
             CASE WHEN NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = m.match_id)
                    OR NOT EXISTS (SELECT 1 FROM match_summary.match_summary s WHERE s.match_id = m.match_id) THEN 'MATCH_SUMMARY' END,
             CASE WHEN NOT EXISTS (SELECT 1 FROM point_by_point.point_by_point_event p WHERE p.match_id = m.match_id) THEN 'POINT_BY_POINT' END,
             CASE WHEN NOT EXISTS (SELECT 1 FROM team_stats.team_stats t WHERE t.match_id = m.match_id) THEN 'TEAM_STATS' END,
             CASE WHEN NOT EXISTS (SELECT 1 FROM stats_player.stats_player sp WHERE sp.match_id = m.match_id) THEN 'PLAYER_STATS' END
           ) AS faltan
    FROM m
    WHERE (m.event_datetime AT TIME ZONE 'Europe/Madrid')::date < (now() AT TIME ZONE 'Europe/Madrid')::date
)
SELECT faltan, count(*) AS partidos FROM e WHERE faltan <> '' GROUP BY faltan ORDER BY partidos DESC;
