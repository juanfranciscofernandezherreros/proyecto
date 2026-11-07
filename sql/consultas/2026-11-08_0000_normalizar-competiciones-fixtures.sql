-- =============================================================================
-- NORMALIZAR COMPETICIONES EN FIXTURES (acb->liga-endesa, super-league->winner-league)
-- =============================================================================
-- Fecha:     2026-11-08 00:00
-- Tipo:      ESCRITURA (con LECTURA de comprobacion)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-08_0000_normalizar-competiciones-fixtures.sql
--
-- PARA QUE SIRVE
--   fixtures y results etiquetan la misma liga con slug distinto: fixtures usa el
--   slug de la URL de Flashscore (acb, super-league) y results el canonico del
--   catalogo (liga-endesa, winner-league). Eso duplica ligas en la web y rompe la
--   union fixture+result por matchId. Ver docs/PLAN-normalizacion-competiciones.md.
-- CUANDO USARLA
--   Tras cargar fixtures con slug no canonico, o como migracion unica de datos ya
--   existentes. El arreglo de raiz (normalizacion en el batch de fixtures) ya evita
--   que reincida en cargas nuevas.
-- COMO LEER EL RESULTADO
--   PASO 1 (antes): cuenta filas con slug no canonico (deben ser >0 antes, 0 despues).
--   PASO 2 (escritura): filas afectadas por cada UPDATE.
--   PASO 3 (despues): no debe quedar ninguna fila con acb/super-league.
-- QUE HACER DESPUES
--   Reproyectar (el projector pasa Postgres->Mongo cada ~60s) y comprobar que
--   /api/v1/matches/filters ya no ofrece acb ni super-league.
-- RESULTADO EL 2026-11-08
--   Antes: acb=258, super-league=160. UPDATE 258 + UPDATE 160. Despues: 0 filas no
--   canonicas. Reproyectado para propagar a Mongo/API.
-- =============================================================================

-- PASO 1 · LECTURA · Filas con slug no canonico (antes).
SELECT competition, count(*) FROM fixtures.fixtures
WHERE competition IN ('acb','super-league')
GROUP BY competition ORDER BY competition;

-- PASO 2 · ESCRITURA · Normalizar al slug canonico.
--   Toca solo fixtures.fixtures con competition no canonica; no afecta a results ni a
--   otras competiciones. Idempotente: si ya estan normalizadas, afecta 0 filas.
UPDATE fixtures.fixtures SET competition = 'liga-endesa'  WHERE competition = 'acb';
UPDATE fixtures.fixtures SET competition = 'winner-league' WHERE competition = 'super-league';

-- PASO 3 · LECTURA · Comprobacion (debe devolver 0 filas).
SELECT competition, count(*) FROM fixtures.fixtures
WHERE competition IN ('acb','super-league')
GROUP BY competition ORDER BY competition;
