-- =============================================================================
-- EUROLIGA: RESULTADOS DE LAS JORNADAS 12 Y 13 (PARA REVISAR EL PRONÓSTICO)
-- =============================================================================
-- Fecha:     2026-11-21 12:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-21_1200_euroliga-jornadas-12-y-13.sql
--
-- PARA QUÉ SIRVE   Comparar el pronóstico publicado de la jornada 12 (euroliga-jornada-12-2026-11-15)
--                  con lo que pasó, y ver la jornada 13 (sin pronóstico publicado). La jornada 12 se
--                  jugó el 17 y 18/11 y la 13 el 19 y 20/11 (fechas de Madrid): diez partidos cada una.
-- CUÁNDO USARLA    Al revisar un pronóstico de Euroliga ya jugado.
-- CÓMO LEER EL RESULTADO  una fila por partido: jornada, día, partido con marcador, margen del
--                  local (positivo = gana el local), cuarto de prórroga si lo hubo y match_id.
-- QUÉ HACER DESPUÉS  Cruzarlo con games[] del artículo de prediction_articles (ganador y margen previstos).
-- RESULTADO EL 2026-11-21  (ver docs/REVISION-PRONOSTICO-EUROLIGA-J12.md)
-- =============================================================================

-- PASO 1 · Los 20 partidos de las jornadas 12 y 13.
SELECT CASE WHEN (event_datetime AT TIME ZONE 'Europe/Madrid')::date <= DATE '2026-11-18' THEN 12 ELSE 13 END AS jornada,
       to_char(event_datetime AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI') AS dia,
       home_team || ' ' || home_score || '-' || away_score || ' ' || away_team AS partido,
       home_score - away_score AS margen_local,
       CASE WHEN home_score5 IS NOT NULL OR away_score5 IS NOT NULL THEN 'prórroga' ELSE '' END AS prorroga,
       match_id
FROM results.results
WHERE competition = 'euroleague'
  AND (event_datetime AT TIME ZONE 'Europe/Madrid')::date BETWEEN DATE '2026-11-17' AND DATE '2026-11-20'
  AND home_score IS NOT NULL
ORDER BY event_datetime;

-- PASO 2 · Ventaja de campo real de la Euroliga (el modelo usa 2,5 puntos): partidos ganados por el
--          local y margen medio del local en todos los partidos cargados, y solo desde el 1 de noviembre.
SELECT CASE WHEN event_datetime >= TIMESTAMPTZ '2026-11-01' THEN 'desde 1/11' ELSE 'antes del 1/11' END AS periodo,
       COUNT(*) AS partidos,
       COUNT(*) FILTER (WHERE home_score > away_score) AS gana_local,
       ROUND(100.0 * COUNT(*) FILTER (WHERE home_score > away_score) / COUNT(*), 1) AS pct_local,
       ROUND(AVG(home_score - away_score), 2) AS margen_medio_local
FROM results.results
WHERE competition = 'euroleague' AND home_score IS NOT NULL
GROUP BY 1 ORDER BY 1;
