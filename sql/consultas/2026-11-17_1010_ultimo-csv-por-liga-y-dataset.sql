-- =============================================================================
-- ÚLTIMO CSV GENERADO POR LIGA Y DATASET
-- =============================================================================
-- Fecha:     2026-11-17 10:10
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1010_ultimo-csv-por-liga-y-dataset.sql
--
-- PARA QUÉ SIRVE   Saber si el corte de detalle de la BSL desde el 10-nov es solo de esa
--                  liga o de todas: fecha del último CSV de cada dataset por liga.
-- CUÁNDO USARLA    Cuando una liga se quede sin jugadas o estadísticas y haya que ver si
--                  el fallo es general.
-- CÓMO LEER EL RESULTADO  Si en todas las ligas PBP/TEAM/PLAYER se paran en la misma fecha,
--                  el fallo es del proceso diario; si solo en una, es de esa liga.
-- QUÉ HACER DESPUÉS       Mirar el log del proceso que genera esos CSV en esa fecha.
-- RESULTADO EL 2026-11-17 Jugadas y estadísticas paradas desde el 9-10 nov en BSL, ACB, Lega A, LKL,
--                  Grecia y Alemania; MATCH-DETAILS y SUMMARY siguen al día. NBA e Israel al día.
-- =============================================================================

-- PASO 1 · Último CSV por liga y dataset (sin RESULTS).
SELECT liga, dataset, max(generado)::date AS ultimo, count(*) AS ficheros
FROM public.v_csv_generados
WHERE dataset <> 'RESULTS' AND generado >= current_date - 14
GROUP BY liga, dataset ORDER BY liga, dataset;
