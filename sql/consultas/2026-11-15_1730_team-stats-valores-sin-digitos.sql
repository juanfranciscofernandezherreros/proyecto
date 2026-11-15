-- =============================================================================
-- TEAM_STATS: ¿HAY VALORES LEGÍTIMOS SIN NINGÚN DÍGITO?
-- =============================================================================
-- Fecha:     2026-11-15 17:30
-- Tipo:      LECTURA (no modifica nada)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-15_1730_team-stats-valores-sin-digitos.sql
--
-- PARA QUÉ SIRVE   Antes de añadir al batch de team_stats la regla "se rechaza la fila
--                  si home_value o away_value no contiene ningún dígito" (paso 2 de
--                  docs\PLAN-mejoras-2026-11.md), comprobar que ninguna fila buena la
--                  incumple. En las filas descuadradas del scraper antiguo la etiqueta
--                  ("Field goal %", "Rebounds") acababa en la columna de valor.
-- CUÁNDO USARLA    Si se cambia la validación del batch o aparece una liga con métricas
--                  cuyo valor no sea numérico.
-- CÓMO LEER EL RESULTADO  PASO 1: filas con valor sin dígitos, separando las de métrica
--                  real de las de métrica-valor. Lo bueno: 0 en `metrica_real`.
--                  PASO 2: ejemplos de valores sin dígitos y su métrica.
-- QUÉ HACER DESPUÉS       Si `metrica_real` > 0, revisar el PASO 2 antes de activar la regla.
-- RESULTADO EL 2026-11-15  metrica_real = 0, metrica_valor = 3787, con_nulos = 0. Los únicos
--                  valores sin dígitos son "Field goal %", "Free throw %" y "Rebounds"
--                  en away_value de filas descuadradas. La regla no rechaza ninguna fila buena.
-- =============================================================================

-- PASO 1 · Filas con algún valor sin dígitos, según el tipo de métrica.
SELECT count(*) FILTER (WHERE metric !~ '^\(?[0-9]+(\.[0-9]+)?[%/]') AS metrica_real,
       count(*) FILTER (WHERE metric  ~ '^\(?[0-9]+(\.[0-9]+)?[%/]') AS metrica_valor,
       count(*) FILTER (WHERE home_value IS NULL OR away_value IS NULL) AS con_nulos
FROM team_stats.team_stats
WHERE home_value !~ '[0-9]' OR away_value !~ '[0-9]'
   OR home_value IS NULL OR away_value IS NULL;

-- PASO 2 · Ejemplos: métrica y valores sin dígitos, los más frecuentes.
SELECT metric ~ '^\(?[0-9]+(\.[0-9]+)?[%/]' AS metrica_es_valor,
       CASE WHEN home_value !~ '[0-9]' THEN home_value END AS home_sin_digitos,
       CASE WHEN away_value !~ '[0-9]' THEN away_value END AS away_sin_digitos,
       count(*) AS filas
FROM team_stats.team_stats
WHERE home_value !~ '[0-9]' OR away_value !~ '[0-9]'
GROUP BY 1, 2, 3
ORDER BY filas DESC
LIMIT 15;
