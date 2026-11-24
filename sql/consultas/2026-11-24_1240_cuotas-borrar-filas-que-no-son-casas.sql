-- =============================================================================
-- CUOTAS: BORRAR LAS FILAS QUE NO SON DE CASAS DE APUESTAS
-- =============================================================================
-- Fecha:     2026-11-24 12:40
-- Tipo:      ESCRITURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-24_1240_cuotas-borrar-filas-que-no-son-casas.sql
--
-- PARA QUÉ SIRVE   El parser de cuotas cargaba filas de la clasificación (vyf2I8i5:
--                  «San Antonio Spurs 18 15 3 …») y de estadísticas de jugadores
--                  (EkvmdDsT: «Davis J. KOR 31 12 2 …») como si fueran casas. Ya está
--                  corregido en python-pyppeter (exige el enlace /bookmaker/<id>/);
--                  esto quita lo ya cargado. Las filas reales traen bookmaker_id.
-- CUÁNDO USARLA    Una vez; antes se mide con 2026-11-24_1230_cuotas-casas-sospechosas.sql.
-- CÓMO LEER EL RESULTADO  Paso 1: filas sin bookmaker_id por partido (antes).
--                  Paso 2: DELETE n (esperado 51). Paso 3: 0 filas sin bookmaker_id.
-- QUÉ HACER DESPUÉS       El projector reproyecta esos 2 partidos en su siguiente ciclo.
-- QUÉ TOCA          Solo filas de odds.odds con bookmaker_id vacío o nulo.
-- RESULTADO EL 2026-11-24 · Antes EkvmdDsT 6 y vyf2I8i5 45; DELETE 51; después 0 filas sin bookmaker_id.
-- =============================================================================

-- PASO 1 · Antes.
SELECT match_id, count(*) AS filas_sin_id
FROM odds.odds
WHERE coalesce(bookmaker_id, '') = ''
GROUP BY match_id ORDER BY match_id;

-- PASO 2 · Borrar.
BEGIN;
DELETE FROM odds.odds WHERE coalesce(bookmaker_id, '') = '';
COMMIT;

-- PASO 3 · Después.
SELECT count(*) AS filas_sin_id FROM odds.odds WHERE coalesce(bookmaker_id, '') = '';
