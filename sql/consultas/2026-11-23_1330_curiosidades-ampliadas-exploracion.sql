-- =============================================================================
-- CURIOSIDADES AMPLIADAS: COLUMNAS DISPONIBLES Y UMBRALES (EXPLORACIÓN)
-- =============================================================================
-- Fecha:     2026-11-23 13:30
-- Tipo:      LECTURA
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-23_1330_curiosidades-ampliadas-exploracion.sql
--
-- PARA QUÉ SIRVE   Antes de ampliar 2026-11-21_1000_curiosidades-cronologicas.sql con
--                  tipos nuevos (jugadores, rachas de equipo, sorpresas, datos raros), ver
--                  qué columnas tienen stats_player.stats_player y
--                  point_by_point.point_by_point_event, y cuántos casos saldrían con cada
--                  umbral para fijarlos sin inundar la lista.
-- CUÁNDO USARLA    Al cambiar umbrales o añadir tipos a la consulta de curiosidades.
-- CÓMO LEER EL RESULTADO  PASO 1-2: columnas. PASO 3: recuento por umbral candidato.
-- QUÉ HACER DESPUÉS       Fijar umbrales en la consulta 2026-11-23_1400_curiosidades-ampliadas.sql.
-- RESULTADO EL 2026-11-23  18 557 líneas de jugador (player_id vacío en 16 375: el jugador
--                  se identifica por nombre + equipo; 145 sin minutos), 1 002 partidos.
--                  Casos: tiro perfecto 8+ 6, 0 de 8+ triples 11, 0 de 10+ de campo 5,
--                  5x5 0, 20-20 2, 20+ rebotes 4, 15+ asistencias 4, 8+ triples 18,
--                  10+ triples 1, 6+ tapones 8, 6+ robos 12, 15+ libres sin fallo 3,
--                  20+ libres 2, 10+ pérdidas 2, +/- 35+ 44, 48+ minutos 2; ganó perdiendo
--                  3 cuartos 37, cuarto de 7 o menos 23 (5 o menos 4), empate al descanso 34.
--                  results.results solo trae una columna de prórroga (score5, acumulada).
-- =============================================================================

-- PASO 1 · Columnas de la línea de cada jugador.
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'stats_player' AND table_name = 'stats_player' ORDER BY ordinal_position;

-- PASO 2 · Columnas del jugada a jugada.
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'point_by_point' AND table_name = 'point_by_point_event' ORDER BY ordinal_position;

-- PASO 3 · Recuento de casos por umbral candidato (jugadores).
WITH l AS (
    SELECT s.*, COALESCE(pts,0) p, COALESCE(reb,0) rb, COALESCE(ast,0) a, COALESCE(st,0) ro,
           COALESCE(bs,0) tp, COALESCE(fgm,0) fm, COALESCE(fga,0) fa, COALESCE(threepm,0) t3,
           COALESCE(threepa,0) t3a, COALESCE(ftm,0) lm, COALESCE(fta,0) la,
           COALESCE(turnovers,0) pe, COALESCE(plus_minus,0) pm,
           substring(min from '^[0-9]+')::int AS minutos
    FROM stats_player.stats_player s
)
SELECT 'lineas' k, COUNT(*) FROM l
UNION ALL SELECT 'perfecto 8+ tiros', COUNT(*) FILTER (WHERE fa >= 8 AND fm = fa) FROM l
UNION ALL SELECT 'perfecto 10+ tiros', COUNT(*) FILTER (WHERE fa >= 10 AND fm = fa) FROM l
UNION ALL SELECT '0 de 8+ triples', COUNT(*) FILTER (WHERE t3a >= 8 AND t3 = 0) FROM l
UNION ALL SELECT '0 de 10+ tiros campo', COUNT(*) FILTER (WHERE fa >= 10 AND fm = 0) FROM l
UNION ALL SELECT '5x5', COUNT(*) FILTER (WHERE p>=5 AND rb>=5 AND a>=5 AND ro>=5 AND tp>=5) FROM l
UNION ALL SELECT '20-20', COUNT(*) FILTER (WHERE p>=20 AND rb>=20) FROM l
UNION ALL SELECT '20+ rebotes', COUNT(*) FILTER (WHERE rb>=20) FROM l
UNION ALL SELECT '15+ asistencias', COUNT(*) FILTER (WHERE a>=15) FROM l
UNION ALL SELECT '10+ triples', COUNT(*) FILTER (WHERE t3>=10) FROM l
UNION ALL SELECT '8+ triples', COUNT(*) FILTER (WHERE t3>=8) FROM l
UNION ALL SELECT '6+ tapones', COUNT(*) FILTER (WHERE tp>=6) FROM l
UNION ALL SELECT '6+ robos', COUNT(*) FILTER (WHERE ro>=6) FROM l
UNION ALL SELECT '20+ tiros libres intentados', COUNT(*) FILTER (WHERE la>=20) FROM l
UNION ALL SELECT '15+/15 libres perfecto', COUNT(*) FILTER (WHERE la>=15 AND lm=la) FROM l
UNION ALL SELECT '10+ perdidas', COUNT(*) FILTER (WHERE pe>=10) FROM l
UNION ALL SELECT '+/- 35 o mas', COUNT(*) FILTER (WHERE ABS(pm)>=35) FROM l
UNION ALL SELECT '48+ minutos', COUNT(*) FILTER (WHERE minutos>=48) FROM l
UNION ALL SELECT 'min nulos', COUNT(*) FILTER (WHERE minutos IS NULL) FROM l
UNION ALL SELECT 'player_id nulos', COUNT(*) FILTER (WHERE player_id IS NULL) FROM l;

-- PASO 4 · Recuento por umbral candidato (partido y equipo).
WITH r AS (
    SELECT r.*, CASE WHEN home_score > away_score THEN 'home' ELSE 'away' END lado
    FROM results.results r WHERE home_score IS NOT NULL AND away_score IS NOT NULL
), c AS (
    SELECT match_id, lado,
      (CASE WHEN lado='home' THEN (home_score1<away_score1)::int+(home_score2<away_score2)::int+(home_score3<away_score3)::int+(home_score4<away_score4)::int
            ELSE (away_score1<home_score1)::int+(away_score2<home_score2)::int+(away_score3<home_score3)::int+(away_score4<home_score4)::int END) AS cuartos_perdidos,
      LEAST(home_score1,away_score1,home_score2,away_score2,home_score3,away_score3,home_score4,away_score4) AS min_cuarto,
      (home_score1+home_score2 = away_score1+away_score2) AS empate_descanso,
      competition
    FROM r WHERE home_score4 IS NOT NULL
)
SELECT 'partidos' k, COUNT(*) FROM c
UNION ALL SELECT 'gano perdiendo 3 cuartos', COUNT(*) FILTER (WHERE cuartos_perdidos >= 3) FROM c
UNION ALL SELECT 'cuarto con 7 o menos', COUNT(*) FILTER (WHERE min_cuarto <= 7) FROM c
UNION ALL SELECT 'cuarto con 5 o menos', COUNT(*) FILTER (WHERE min_cuarto <= 5) FROM c
UNION ALL SELECT 'empate al descanso', COUNT(*) FILTER (WHERE empate_descanso) FROM c;

-- PASO 5 · Formato de la columna min (texto «mm:ss»): muestra al azar.
SELECT min FROM stats_player.stats_player WHERE min IS NOT NULL ORDER BY random() LIMIT 8;

-- PASO 6 · Columnas de results.results (cuartos y prórrogas).
SELECT string_agg(column_name, ', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'results' AND table_name = 'results';
