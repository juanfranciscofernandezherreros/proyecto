-- =============================================================================
-- BSL (TURQUÍA): QUÉ DATASETS SE QUEDARON A MEDIAS
-- =============================================================================
-- Fecha:     2026-11-17 10:00
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-17_1000_bsl-a-medias.sql
--
-- PARA QUÉ SIRVE   El usuario indica que la BSL (turkey/super-lig) quedó a medias. Se mira
--                  qué CSV se generaron por dataset y en qué estado quedaron en el launcher.
-- CUÁNDO USARLA    Cuando una liga concreta parezca incompleta tras una extracción.
-- CÓMO LEER EL RESULTADO  Paso 1: por dataset, CSV generados y su estado. SIN ENVIAR o
--                  FAILED = a medias. Paso 2: últimos ficheros de la liga.
-- QUÉ HACER DESPUÉS       Reimportar lo que no esté COMPLETED o reextraer el dataset que falte.
-- RESULTADO EL 2026-11-17 Desde el 10-nov solo hay SCORE_SUMMARY (24) y MATCH_DETAILS (42, todos
--                  SIN ENVIAR); PBP, TEAM_STATS y PLAYER_STATS se quedan en 16: ~8 partidos sin detalle.
-- =============================================================================

-- PASO 1 · CSV de la BSL por dataset y estado (últimos 7 días).
SELECT dataset, estado, count(*) AS ficheros, max(generado) AS ultimo
FROM public.v_csv_generados
WHERE liga ILIKE '%turkey%' AND generado >= current_date - 7
GROUP BY dataset, estado ORDER BY dataset, estado;

-- PASO 2 · Últimos 15 ficheros de la BSL.
SELECT *
FROM public.v_csv_generados
WHERE liga ILIKE '%turkey%'
ORDER BY generado DESC LIMIT 15;
