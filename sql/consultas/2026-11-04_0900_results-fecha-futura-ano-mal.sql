-- =============================================================================
-- RESULTS CON FECHA FUTURA POR AÑO MAL INFERIDO
-- =============================================================================
-- Fecha:     2026-11-04 09:00
-- Tipo:      LECTURA + ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-04_0900_results-fecha-futura-ano-mal.sql
--
-- PARA QUÉ SIRVE
--   Flashscore muestra la fecha de los partidos sin año ("05.05. 17:45"). El scraper
--   infería el año eligiendo la ocurrencia MÁS CERCANA entre año-1, año y año+1. Para un
--   partido jugado cuya fecha cae a ~6 meses vista (p. ej. mayo visto en noviembre), la
--   ocurrencia futura gana por unas horas, y un partido ya FINALIZADO acaba fechado en el
--   futuro. En results.results (schema que lee el projector hacia Mongo y la web) eso deja
--   partidos con marcador pero event_datetime en 2027, imposible. El scraper ya se corrigió
--   (parse_flashscore_datetime con prefer="past" en los RESULTS); esto arregla lo ya guardado.
--
-- CUÁNDO USARLA
--   Cuando en la web aparezcan partidos finalizados con fecha futura, o tras detectar filas
--   en results.results con event_datetime > now(). Un partido finalizado NUNCA puede estar
--   en el futuro, así que esa condición es el criterio seguro de "fecha mal".
--
-- CÓMO LEER EL RESULTADO
--   PASO 1 lista las filas sospechosas (todas deberían ser del futuro). PASO 3 debe devolver
--   0 filas: si no, quedan fechas futuras sin corregir.
--
-- QUÉ HACER DESPUÉS
--   Tras el UPDATE, el projector re-proyecta a Mongo en su siguiente ciclo (~60 s, incluye
--   event_datetime en su hash de cambios), y la web mostrará la fecha correcta sola.
--
-- RESULTADO EL 2026-11-04  PASO 1 listó 6 filas (serbia/superleague, 2027-04/05). PASO 2
--   corrigió 6 (UPDATE 6): 2027 -> 2026. PASO 3 devolvió 0 filas futuras restantes.

-- PASO 1 · LECTURA · Partidos finalizados con fecha futura (imposible). Antes de tocar nada.
SELECT match_id, event_datetime, home_team, away_team, country, competition
FROM results.results
WHERE event_datetime > now()
ORDER BY event_datetime;

-- PASO 2 · ESCRITURA · Corrige el año restando 1 año SOLO a las filas futuras. El bug elige
--   siempre la ocurrencia de dentro de un año, así que la fecha real es la del año anterior.
--   La condición event_datetime > now() protege las fechas pasadas (correctas): no se tocan.
UPDATE results.results
SET event_datetime = event_datetime - interval '1 year'
WHERE event_datetime > now();

-- PASO 3 · LECTURA · Comprobación: debe devolver 0 filas.
SELECT count(*) AS filas_futuras_restantes
FROM results.results
WHERE event_datetime > now();
