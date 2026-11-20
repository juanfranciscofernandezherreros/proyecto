-- =============================================================================
-- CORREGIR *_points_added EN LA PRIMERA JUGADA DE CADA CUARTO
-- =============================================================================
-- Fecha:     2026-11-20 23:55
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-20_2355_corregir-points-added.sql
--
-- PARA QUÉ SIRVE   En point_by_point.point_by_point_event, la primera jugada de algunos
--                  cuartos guardaba en home_points_added / away_points_added el marcador
--                  acumulado (p. ej. pxFIMqFt, 4th Quarter, seq 1 → +104/+104) porque el
--                  extractor empezaba cada cuarto comparando con 0-0. Ya está corregido en
--                  origen (python-pyppeter d8af978); esto arregla lo ya cargado sin
--                  reextraer. Plan: docs/PLAN-puntos-anadidos-inicio-cuarto.md.
-- CUÁNDO USARLA    Si el PASO 1 (o el PASO 5 de 2026-11-20_2300_curiosidades-jugada-a-jugada.sql)
--                  vuelve a dar points_added_mal > 0, p. ej. tras cargar CSV antiguos.
-- CÓMO LEER EL RESULTADO  PASO 1/3: points_added_mal debe quedar en 0. PASO 2: «UPDATE n» =
--                  jugadas corregidas. PASO 4: la 1ª jugada del 4º cuarto de pxFIMqFt
--                  con +2/+3 o similar.
-- QUÉ HACER DESPUÉS       Nada: el projector incluye el jugada a jugada en su sourceHash y
--                  reproyecta solo a Mongo los partidos cambiados en su siguiente ciclo.
-- RESULTADO EL 2026-11-20 2643 jugadas corregidas, 0 mal después (detalle al final)
-- =============================================================================

-- PASO 1 · Antes: cuántas jugadas no cuadran con la diferencia de marcador respecto a la
--          jugada anterior del partido (orden quarter, sequence; la primera del partido
--          se compara con 0-0).
WITH d AS (
    SELECT match_id, quarter, sequence, home_points_added, away_points_added,
           home_score - COALESCE(LAG(home_score) OVER w, 0) AS dl,
           away_score - COALESCE(LAG(away_score) OVER w, 0) AS dv
    FROM point_by_point.point_by_point_event
    WINDOW w AS (PARTITION BY match_id ORDER BY quarter, sequence)
)
SELECT COUNT(*) AS jugadas,
       COUNT(*) FILTER (WHERE home_points_added IS DISTINCT FROM dl OR away_points_added IS DISTINCT FROM dv) AS points_added_mal,
       COUNT(DISTINCT match_id) FILTER (WHERE home_points_added IS DISTINCT FROM dl OR away_points_added IS DISTINCT FROM dv) AS partidos_afectados
FROM d;

-- PASO 2 · ESCRITURA. Recalcula *_points_added como diferencia con la jugada anterior.
--          Qué filas toca: solo las que no cuadran (IS DISTINCT FROM), así que volver a
--          lanzarlo no cambia nada. No toca marcadores, líder ni ventaja. Transacción:
--          si algo falla no queda a medias.
BEGIN;
WITH d AS (
    SELECT match_id, quarter, sequence,
           home_score - COALESCE(LAG(home_score) OVER w, 0) AS dl,
           away_score - COALESCE(LAG(away_score) OVER w, 0) AS dv
    FROM point_by_point.point_by_point_event
    WINDOW w AS (PARTITION BY match_id ORDER BY quarter, sequence)
)
UPDATE point_by_point.point_by_point_event e
SET home_points_added = d.dl,
    away_points_added = d.dv
FROM d
WHERE e.match_id = d.match_id AND e.quarter = d.quarter AND e.sequence = d.sequence
  AND (e.home_points_added IS DISTINCT FROM d.dl OR e.away_points_added IS DISTINCT FROM d.dv);
COMMIT;

-- PASO 3 · Después: debe dar points_added_mal = 0.
WITH d AS (
    SELECT match_id, quarter, sequence, home_points_added, away_points_added,
           home_score - COALESCE(LAG(home_score) OVER w, 0) AS dl,
           away_score - COALESCE(LAG(away_score) OVER w, 0) AS dv
    FROM point_by_point.point_by_point_event
    WINDOW w AS (PARTITION BY match_id ORDER BY quarter, sequence)
)
SELECT COUNT(*) AS jugadas,
       COUNT(*) FILTER (WHERE home_points_added IS DISTINCT FROM dl OR away_points_added IS DISTINCT FROM dv) AS points_added_mal
FROM d;

-- PASO 4 · Ejemplo: final del 3º y comienzo del 4º cuarto de pxFIMqFt.
SELECT quarter, sequence, home_score, away_score, home_points_added, away_points_added
FROM point_by_point.point_by_point_event
WHERE match_id = 'pxFIMqFt'
  AND ((quarter = '3rd Quarter' AND sequence >= (SELECT MAX(sequence) - 1 FROM point_by_point.point_by_point_event
                                                  WHERE match_id = 'pxFIMqFt' AND quarter = '3rd Quarter'))
       OR (quarter = '4th Quarter' AND sequence <= 2))
ORDER BY quarter, sequence;

-- RESULTADO EL 2026-11-20 23:58
--   PASO 1: 87982 jugadas, 2643 mal en 882 partidos.  PASO 2: UPDATE 2643.
--   PASO 3: points_added_mal = 0.  PASO 4: pxFIMqFt 4th Quarter seq 1 → 104-104 con
--   +0/+2 (antes +104/+104), seq 2 → +0/+2.
