-- =============================================================================
-- DATOS PARA EL PRONÓSTICO DE LA PRÓXIMA JORNADA DE EUROLIGA
-- =============================================================================
-- Fecha:     2026-11-15 22:45
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_2245_pronostico-euroliga-proxima-jornada.sql
--
-- PARA QUÉ SIRVE   Reunir lo que hace falta para pronosticar la siguiente jornada de
--                  Euroliga: qué partidos se juegan (fixtures.fixtures sin resultado y
--                  con fecha futura) y cómo llega cada equipo (results.results de la
--                  misma competición): balance, puntos a favor y en contra, diferencial
--                  medio de temporada y de los últimos cinco partidos, y balance como
--                  local y como visitante. Es el mismo criterio numérico que documenta
--                  csv-extra-batch\pronostico\README.md (65 % diferencial de temporada,
--                  35 % últimos cinco, 2,5 puntos de localía).
-- CUÁNDO USARLA    Antes de escribir la previa de una jornada, con results al día
--                  (skill `resultados-todas-las-ligas`).
-- CÓMO LEER EL RESULTADO
--                  Paso 1: los partidos de los próximos 10 días; la jornada son los que
--                  caen en el mismo bloque de 2-3 días. Paso 2: una fila por equipo;
--                  `dif_temp` y `dif_ult5` son puntos por partido (positivo = gana por
--                  esa media). Un equipo con pocos partidos (`pj` bajo) da una media
--                  poco fiable. Paso 3: comprueba que los nombres de equipo del
--                  calendario existen en los resultados; si sale alguna fila, ese
--                  equipo está escrito distinto y sus datos no se han cruzado.
-- QUÉ HACER DESPUÉS
--                  Margen esperado = 0,65·(dif_temp local − dif_temp visitante)
--                  + 0,35·(dif_ult5 local − dif_ult5 visitante) + 2,5.
--                  Probabilidad local = 1 / (1 + exp(−margen / 9)).
-- RESULTADO EL 2026-11-15 22:45   ver al final del fichero.
-- =============================================================================

-- PASO 1 · Partidos de Euroliga de los próximos 10 días que aún no tienen resultado.
SELECT f.match_id,
       to_char(f.event_datetime AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI') AS fecha,
       f.home_team,
       f.away_team
FROM fixtures.fixtures f
WHERE f.country = 'europe' AND f.competition = 'euroleague'
  AND f.event_datetime > now()
  AND f.event_datetime < now() + interval '10 days'
  AND NOT EXISTS (SELECT 1 FROM results.results r WHERE r.match_id = f.match_id)
ORDER BY f.event_datetime, f.home_team;

-- PASO 2 · Estado de forma de cada equipo en la Euroliga (solo partidos con marcador).
WITH lados AS (
    SELECT r.match_id, r.event_datetime, r.home_team AS equipo, true AS local,
           r.home_score AS pf, r.away_score AS pc
    FROM results.results r
    WHERE r.country = 'europe' AND r.competition = 'euroleague'
      AND r.home_score IS NOT NULL AND r.away_score IS NOT NULL
    UNION ALL
    SELECT r.match_id, r.event_datetime, r.away_team, false,
           r.away_score, r.home_score
    FROM results.results r
    WHERE r.country = 'europe' AND r.competition = 'euroleague'
      AND r.home_score IS NOT NULL AND r.away_score IS NOT NULL
), numerados AS (
    SELECT l.*, row_number() OVER (PARTITION BY equipo ORDER BY event_datetime DESC) AS orden
    FROM lados l
)
SELECT equipo,
       count(*)                                                         AS pj,
       count(*) FILTER (WHERE pf > pc)                                  AS g,
       count(*) FILTER (WHERE pf < pc)                                  AS p,
       round(avg(pf), 1)                                                AS pf,
       round(avg(pc), 1)                                                AS pc,
       round(avg(pf - pc), 1)                                           AS dif_temp,
       round(avg(pf - pc) FILTER (WHERE orden <= 5), 1)                 AS dif_ult5,
       count(*) FILTER (WHERE orden <= 5 AND pf > pc)                   AS g_ult5,
       count(*) FILTER (WHERE local AND pf > pc) || '-' ||
       count(*) FILTER (WHERE local AND pf < pc)                        AS casa,
       count(*) FILTER (WHERE NOT local AND pf > pc) || '-' ||
       count(*) FILTER (WHERE NOT local AND pf < pc)                    AS fuera
FROM numerados
GROUP BY equipo
ORDER BY count(*) FILTER (WHERE pf > pc) DESC, avg(pf - pc) DESC;

-- PASO 3 · Equipos del calendario próximo cuyo nombre no aparece en los resultados.
SELECT DISTINCT equipo
FROM (
    SELECT f.home_team AS equipo FROM fixtures.fixtures f
    WHERE f.country = 'europe' AND f.competition = 'euroleague'
      AND f.event_datetime > now() AND f.event_datetime < now() + interval '10 days'
    UNION
    SELECT f.away_team FROM fixtures.fixtures f
    WHERE f.country = 'europe' AND f.competition = 'euroleague'
      AND f.event_datetime > now() AND f.event_datetime < now() + interval '10 days'
) proximos
WHERE NOT EXISTS (
    SELECT 1 FROM results.results r
    WHERE r.country = 'europe' AND r.competition = 'euroleague'
      AND (r.home_team = proximos.equipo OR r.away_team = proximos.equipo)
);

-- RESULTADO EL 2026-11-15 22:45
--   Paso 1: 30 partidos en 10 días. La jornada 12 son los 10 del 17 y 18 de noviembre
--           (9 el 17/11 y Besiktas - Real Madrid el 18/11); la 13 se juega el 19 y 20.
--   Paso 2: 20 equipos, todos con 11 partidos (110 resultados). Mejor diferencial de
--           temporada: Real Madrid (+8,4); peor: Baskonia (-12,0).
--   Paso 3: 0 filas; todos los nombres del calendario cruzan con los resultados.
--   Con estos datos se publicó el artículo `euroliga-jornada-12-2026-11-15` en la
--   colección prediction_articles de MongoDB.
