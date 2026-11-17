-- =============================================================================
-- PARTIDOS DE AYER (2026-11-16) EN FIXTURES Y SI YA TIENEN RESULTADO
-- =============================================================================
-- Fecha:     2026-11-17 09:05
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_0905_partidos-ayer-fixtures-vs-results.sql
--
-- PARA QUÉ SIRVE   Listar los partidos programados en fixtures para el día de ayer
--                  (hora de Madrid) y cruzarlos con results.results para saber cuáles
--                  ya tienen marcador. Sirve para decidir qué resultados hay que
--                  extraer: los que están en fixtures y no en results.
-- CUÁNDO USARLA    Al día siguiente de una jornada, para ver qué se ha jugado.
-- CÓMO LEER EL RESULTADO
--                  · con_resultado = 'SI'  → el partido ya está en results.results.
--                  · con_resultado = 'NO'  → está en fixtures y falta su marcador;
--                    si la fecha ya pasó, hay que extraerlo.
--                  Cambiar la fecha de ayer en PASO 1 si se quiere otro día.
-- QUÉ HACER DESPUÉS
--                  Si hay 'NO' en partidos de ayer → skill `extraer-resultados`
--                  (liga concreta) o `resultados-todas-las-ligas`.
-- RESULTADO EL 2026-11-17 09:05   ver al final del fichero.
-- =============================================================================

-- PASO 1 · Partidos de fixtures cuya fecha local (Europe/Madrid) es ayer, con su
-- marcador si ya existe en results.results.
SELECT to_char(f.event_datetime AT TIME ZONE 'Europe/Madrid', 'DD/MM HH24:MI') AS partido,
       f.country || '/' || f.competition                                       AS liga,
       f.home_team || ' - ' || f.away_team                                     AS enfrentamiento,
       CASE WHEN r.match_id IS NULL THEN 'NO' ELSE 'SI' END                    AS con_resultado,
       r.home_score || '-' || r.away_score                                     AS marcador,
       f.match_id
FROM fixtures.fixtures f
LEFT JOIN results.results r ON r.match_id = f.match_id
WHERE (f.event_datetime AT TIME ZONE 'Europe/Madrid')::date = DATE '2026-11-16'
ORDER BY f.country, f.competition, f.event_datetime;
