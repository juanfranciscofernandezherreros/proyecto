-- =============================================================================
-- LAKERS: PARTIDOS DE LA NBA CARGADOS Y FECHAS (COMPROBAR LA CLASIFICACIÓN DEL GUION)
-- =============================================================================
-- Fecha:     2026-11-21 11:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-21_1130_nba-lakers-partidos-cargados.sql
--
-- PARA QUÉ SIRVE   La clasificación del PASO 3 de 2026-11-21_1100_datos-guion-video.sql da a los
--                  Lakers 15-6 en 21 partidos, mientras que la prensa (AP, 17/11) decía 13-2 tras
--                  15 partidos. Esta consulta lista los partidos de los Lakers cargados, con fecha,
--                  para ver si hay partidos de más (pretemporada, Copa NBA, duplicados) o si faltan.
-- CUÁNDO USARLA    Si la clasificación calculada no cuadra con la oficial.
-- CÓMO LEER EL RESULTADO  una fila por partido; fijarse en las fechas más antiguas y en
--                  match_id repetidos o con marcadores raros.
-- QUÉ HACER DESPUÉS  Si hay partidos que no son de liga regular, no usar la clasificación
--                  calculada para la NBA; revisar con la skill diagnosticar-partido.
-- RESULTADO EL 2026-11-21  (ver docs/guion-video-semana-2026-11-14_20.md, notas)
-- =============================================================================

-- PASO 1 · Partidos de los Lakers cargados, del más antiguo al más reciente.
SELECT to_char((event_datetime AT TIME ZONE 'Europe/Madrid')::date, 'DD/MM/YYYY') AS fecha,
       home_team || ' ' || home_score || '-' || away_score || ' ' || away_team AS partido,
       match_id
FROM results.results
WHERE competition = 'nba' AND 'Los Angeles Lakers' IN (home_team, away_team)
ORDER BY event_datetime;

-- PASO 2 · Primera fecha de partido de la NBA cargada y número de partidos por mes.
SELECT to_char(date_trunc('month', event_datetime AT TIME ZONE 'Europe/Madrid'), 'YYYY-MM') AS mes,
       COUNT(*) AS partidos, MIN((event_datetime AT TIME ZONE 'Europe/Madrid')::date) AS primero
FROM results.results WHERE competition = 'nba' GROUP BY 1 ORDER BY 1;

-- PASO 3 · Partidos de la NBA por día entre el 15 y el 24 de octubre (dónde acaba la
--          pretemporada y empieza la liga regular; la liga regular empieza con un día
--          de muchos partidos).
SELECT (event_datetime AT TIME ZONE 'Europe/Madrid')::date AS dia, COUNT(*) AS partidos
FROM results.results
WHERE competition = 'nba'
  AND (event_datetime AT TIME ZONE 'Europe/Madrid')::date BETWEEN DATE '2026-10-15' AND DATE '2026-10-24'
GROUP BY 1 ORDER BY 1;

-- PASO 4 · Los partidos de la NBA del 20 y el 21 de octubre (¿inauguración o pretemporada?).
SELECT to_char(event_datetime AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI') AS hora_madrid,
       home_team || ' ' || home_score || '-' || away_score || ' ' || away_team AS partido, match_id
FROM results.results
WHERE competition = 'nba'
  AND (event_datetime AT TIME ZONE 'Europe/Madrid')::date BETWEEN DATE '2026-10-20' AND DATE '2026-10-21'
ORDER BY event_datetime;
