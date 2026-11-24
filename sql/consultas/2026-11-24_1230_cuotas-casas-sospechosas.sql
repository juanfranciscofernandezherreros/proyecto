-- =============================================================================
-- CUOTAS: ¿HAY FILAS QUE NO SON DE CASAS DE APUESTAS?
-- =============================================================================
-- Fecha:     2026-11-24 12:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1230_cuotas-casas-sospechosas.sql
--
-- PARA QUÉ SIRVE   El parser de cuotas (python-pyppeter/extract_flashscore_odds.py)
--                  acepta cualquier fila .ui-table__row, y la clasificación de la
--                  página de Flashscore usa esa misma clase: si no hay cuotas (o además
--                  de ellas) mete equipos como si fueran casas («San Antonio Spurs» con
--                  cuotas 3 / 0.833). Esta consulta mide cuánta basura hay.
-- CUÁNDO USARLA    Tras cargar CSV de cuotas.
-- CÓMO LEER EL RESULTADO  Paso 1: casas por número de filas y si traen bookmaker_id
--                  (las reales lo traen) y raw_text con «:» de clasificación. Paso 2:
--                  filas y partidos afectados.
-- QUÉ HACER DESPUÉS       Si hay basura: arreglar el parser y limpiar odds.odds.
-- RESULTADO EL 2026-11-24 · 51 filas sin bookmaker_id en 2 partidos (vyf2I8i5 45: clasificación NBA; EkvmdDsT 6: estadísticas de jugadores); el resto, 38057 filas, con id.
-- =============================================================================

-- PASO 1 · «Casas» con y sin bookmaker_id.
SELECT bookmaker, coalesce(nullif(bookmaker_id, ''), '(sin id)') AS bookmaker_id,
       count(*) AS filas, count(DISTINCT match_id) AS partidos,
       bool_or(raw_text ~ '[0-9]+:[0-9]+') AS parece_clasificacion
FROM odds.odds
GROUP BY 1, 2
ORDER BY coalesce(nullif(bookmaker_id, ''), '(sin id)') = '(sin id)' DESC, filas DESC
LIMIT 40;

-- PASO 2 · Filas sin bookmaker_id (sospechosas) frente al total.
SELECT count(*) FILTER (WHERE coalesce(bookmaker_id, '') = '') AS filas_sin_id,
       count(DISTINCT match_id) FILTER (WHERE coalesce(bookmaker_id, '') = '') AS partidos_con_basura,
       count(*) AS filas_total
FROM odds.odds;
