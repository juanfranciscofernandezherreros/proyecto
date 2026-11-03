-- =============================================================================
-- PARTIDOS SIN HORA EN results.results (event_time / event_datetime vacíos)
-- =============================================================================
-- Fecha:     2026-11-03 09:25
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_0925_partidos-sin-event-time.sql
--
-- PARA QUÉ SIRVE
--   La tabla results.results guarda el resultado final de cada partido. Dos columnas
--   indican cuándo se jugó:
--     · event_time      hora local de Madrid como texto ('20:30:00')
--     · event_datetime  fecha y hora completas con zona horaria (timestamptz)
--   Si faltan, el partido no se puede ordenar en el tiempo ni cruzar bien con fixtures.
--   Esta consulta cuenta cuántos partidos no tienen hora, de qué competiciones son y,
--   sobre todo, POR QUÉ les falta, para saber cómo arreglarlo.
--
-- CUÁNDO USARLA
--   · Después de importar RESULTS de una o varias ligas, para comprobar que llegó la hora.
--   · Si en Grafana o en la web aparecen partidos sin fecha.
--   · Antes y después de corregir el scraper o el importador, para medir el efecto.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  sin_event_time y sin_event_datetime deberían ser 0. Lo normal es que coincidan.
--   PASO 2  qué competiciones concentran el problema.
--   PASO 3  la columna con_prorroga es la clave del diagnóstico:
--             · Si casi todos tienen prórroga, el fallo está en el SCRAPER de resultados
--               (Flashscore pega la marca "AOT" a la hora y el scraper no la reconocía;
--               corregido en python-pyppeter, tarea KAN-343).
--             · Si son partidos SIN prórroga escritos un día concreto, probablemente vienen
--               del pipeline por partido (python\run_match_pipeline.py), que publica la hora
--               vacía; el importador ya no la sobrescribe (COALESCE en ResultsWriter).
--   PASO 4  listado partido a partido; fecha_en_fixtures indica si la hora se puede
--           recuperar desde la tabla fixtures sin volver a extraer nada.
--
-- QUÉ HACER DESPUÉS
--   · Si fecha_en_fixtures tiene valor → 2026-11-03_0945_completar-event-time-desde-fixtures.sql
--   · Si no lo tiene → volver a extraer los RESULTS de esa liga:
--       1_EJECUTAR\LIGAS_ORQUESTAR.bat <LIGA> results 10
--     y seguir el avance con 2026-11-03_1015_avance-reextraccion-event-datetime.sql
--
-- RESULTADO EL 2026-11-03
--   45 de 635 partidos sin hora. 36 con prórroga (y ningún partido con prórroga tenía hora).
--   Los otros 9 eran de la Euroliga, sin prórroga, escritos el 2026-11-01 por el pipeline
--   por partido. 16 tenían fecha en fixtures.
-- =============================================================================


-- PASO 1 · Recuento general: cuántos partidos no tienen hora frente al total.
SELECT count(*) FILTER (WHERE coalesce(trim(event_time), '') = '') AS sin_event_time,
       count(*) FILTER (WHERE event_datetime IS NULL)               AS sin_event_datetime,
       count(*)                                                      AS total
FROM results.results;


-- PASO 2 · Por competición: dónde se concentra el problema.
SELECT country, competition, count(*) AS sin_hora
FROM results.results
WHERE coalesce(trim(event_time), '') = ''
GROUP BY 1, 2
ORDER BY 3 DESC;


-- PASO 3 · Diagnóstico de la causa. Un partido tiene prórroga si hay puntos en el quinto
--          periodo (home_score5 / away_score5). Se agrupa por el día en que se escribió la
--          fila (updated_at) para distinguir importaciones distintas.
SELECT updated_at::date AS escrito,
       count(*) FILTER (WHERE home_score5 IS NOT NULL OR away_score5 IS NOT NULL) AS con_prorroga,
       count(*) FILTER (WHERE home_score5 IS NULL AND away_score5 IS NULL)         AS sin_prorroga
FROM results.results
WHERE coalesce(trim(event_time), '') = ''
GROUP BY 1
ORDER BY 1;


-- PASO 4 · Listado partido a partido. El LEFT JOIN con fixtures muestra la fecha
--          programada del partido si existe: esos se pueden completar sin reextraer.
SELECT r.match_id, r.country, r.competition,
       r.home_team || ' - ' || r.away_team AS partido,
       r.home_score || '-' || r.away_score AS marcador,
       to_char(f.event_datetime AT TIME ZONE 'Europe/Madrid', 'YYYY-MM-DD HH24:MI') AS fecha_en_fixtures
FROM results.results r
LEFT JOIN fixtures.fixtures f ON f.match_id = r.match_id
WHERE coalesce(trim(r.event_time), '') = ''
ORDER BY r.country, r.competition, r.match_id;
