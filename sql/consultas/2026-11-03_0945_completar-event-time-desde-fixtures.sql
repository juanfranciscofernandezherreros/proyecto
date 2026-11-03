-- =============================================================================
-- COMPLETAR LA HORA DE results CON LA FECHA DE fixtures
-- =============================================================================
-- Fecha:     2026-11-03 09:45
-- Tipo:      ESCRITURA (modifica results.results)
-- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\2026-11-03_0945_completar-event-time-desde-fixtures.sql
--
-- PARA QUÉ SIRVE
--   Algunos partidos llegan a results.results sin event_time / event_datetime, pero su
--   fecha sí está en fixtures.fixtures (el calendario, que se extrae aparte). Esta
--   consulta copia esa fecha a results, sin tener que volver a extraer nada de Flashscore.
--
-- CUÁNDO USARLA
--   Cuando 2026-11-03_0925_partidos-sin-event-time.sql (PASO 4) muestra partidos sin hora
--   que SÍ tienen valor en fecha_en_fixtures.
--
-- QUÉ TOCA Y QUÉ PROTEGE
--   · Solo filas de results con event_time vacío Y event_datetime vacío: nunca sobrescribe
--     una hora que ya exista.
--   · Solo si fixtures tiene fecha (f.event_datetime IS NOT NULL).
--   · event_time se guarda como hora LOCAL de Madrid ('HH24:MI:SS'), igual que el resto de
--     filas; event_datetime se copia tal cual (timestamptz).
--   · Es repetible: una segunda ejecución no cambia nada, porque esas filas ya tienen hora.
--
-- CÓMO LEER EL RESULTADO
--   PASO 1  comprobación previa: hora_local_fixture debe coincidir con event_time. Si no
--           coinciden, el formato o la zona horaria no son los esperados → NO sigas.
--   PASO 2  la línea "UPDATE n" dice cuántas filas se completaron; RETURNING las lista.
--   PASO 3  cuántos partidos siguen sin hora (los que no tenían fecha en fixtures).
--
-- QUÉ HACER DESPUÉS
--   Los que sigan sin hora no tienen otra fuente en la base de datos: hay que volver a
--   extraer los RESULTS de su liga (1_EJECUTAR\LIGAS_ORQUESTAR.bat <LIGA> results 10) y
--   seguir el avance con 2026-11-03_1015_avance-reextraccion-event-datetime.sql.
--
-- RESULTADO EL 2026-11-03
--   UPDATE 16 (de 45 sin hora). Quedaron 29, todos con prórroga y sin fecha en fixtures.
-- =============================================================================


-- PASO 1 · Comprobación previa (solo lectura). Con partidos que SÍ tienen hora, se compara
--          su event_time con la hora local que daría fixtures. Deben ser iguales.
SELECT r.match_id, r.event_time, r.event_datetime,
       to_char(f.event_datetime AT TIME ZONE 'Europe/Madrid', 'HH24:MI:SS') AS hora_local_fixture
FROM results.results r
JOIN fixtures.fixtures f USING (match_id)
WHERE coalesce(trim(r.event_time), '') <> ''
LIMIT 3;


-- PASO 2 · La corrección. Copia la fecha de fixtures a los partidos de results que no la
--          tienen; las condiciones del WHERE garantizan que no se pisa ninguna hora existente.
UPDATE results.results r
SET event_datetime = f.event_datetime,
    event_time     = to_char(f.event_datetime AT TIME ZONE 'Europe/Madrid', 'HH24:MI:SS'),
    updated_at     = now()
FROM fixtures.fixtures f
WHERE f.match_id = r.match_id
  AND f.event_datetime IS NOT NULL
  AND coalesce(trim(r.event_time), '') = ''
  AND r.event_datetime IS NULL
RETURNING r.match_id, r.country, r.competition, r.event_time, r.event_datetime;


-- PASO 3 · Verificación: cuántos partidos siguen sin hora después de la corrección.
SELECT count(*) AS quedan_sin_hora
FROM results.results
WHERE coalesce(trim(event_time), '') = '';
