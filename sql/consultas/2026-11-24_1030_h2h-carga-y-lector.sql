-- =============================================================================
-- H2H: COMPROBAR LA CARGA Y LA CONSULTA DEL PROJECTOR
-- =============================================================================
-- Fecha:     2026-11-24 10:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1030_h2h-carga-y-lector.sql
--
-- PARA QUÉ SIRVE   Tras cargar los H2H_*.csv con el extra-importer (schema h2h),
--                  comprobar filas, ficheros y partidos, y probar la consulta que usa
--                  el projector (PostgresMatchReader.H2H_SQL) con un partido real.
-- CUÁNDO USARLA    Después de cargar CSV H2H o de cambiar la consulta del projector.
-- CÓMO LEER EL RESULTADO  Paso 1: filas, ficheros y partidos (esperado: 394 ficheros,
--                  276 partidos). Paso 2: partidos con más de un CSV (el projector usa
--                  el más reciente). Paso 3: filas que proyectaría para ABQKswin, con
--                  «Last matches» primero, el cara a cara al final y fechas descendentes.
-- QUÉ HACER DESPUÉS       Si cuadra, desplegar el projector y mirar matches.h2h en Mongo.
-- RESULTADO EL 2026-11-24 · Con la carga a medias (40 ficheros): 580 filas, 40 partidos, ninguno con varios CSV; ABQKswin devuelve 15 filas (Trieste 5, Venezia 5, cara a cara 5) en el orden esperado.
-- =============================================================================

-- PASO 1 · Volumen cargado.
SELECT count(*) AS filas,
       count(DISTINCT source_file) AS ficheros,
       count(DISTINCT match_id) AS partidos
FROM h2h.h2h;

-- PASO 2 · Partidos con varios CSV H2H (extraídos en días distintos).
SELECT count(*) AS partidos_con_varios_csv
FROM (SELECT match_id FROM h2h.h2h GROUP BY match_id HAVING count(DISTINCT source_file) > 1) varios;

-- PASO 3 · Consulta del projector (PostgresMatchReader.H2H_SQL) para ABQKswin.
WITH latest AS (
    SELECT source_file
    FROM h2h.h2h
    WHERE match_id = 'ABQKswin'
    GROUP BY source_file
    ORDER BY coalesce(substring(source_file from 'H2H_([0-9]{14})_'), '') DESC, source_file DESC
    LIMIT 1
)
SELECT section, event_date, competition, home_team, away_team, note,
       home_score, away_score, result_for_section_team
FROM h2h.h2h
WHERE match_id = 'ABQKswin' AND source_file = (SELECT source_file FROM latest)
ORDER BY CASE WHEN section ILIKE 'Head-to-head%' THEN 1 ELSE 0 END,
         section,
         CASE WHEN event_date ~ '^[0-9]{2}[.][0-9]{2}[.][0-9]{2}$'
              THEN to_date(event_date, 'DD.MM.YY') END DESC NULLS LAST;
