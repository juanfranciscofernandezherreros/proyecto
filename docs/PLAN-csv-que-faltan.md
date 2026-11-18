# Plan: skill de CSV que faltan por generar

Pedido el 2026-11-18. En la web, `/matches/Gr62XNa6` (Barcelona - Paris, euroleague,
2026-11-17) no tiene jugadas ni estadísticas y el usuario creía que `basket pendientes`
lo había procesado.

## Diagnóstico de Gr62XNa6

- No se procesó: en `PROCESAR_MATCHIDS_20261118080204.csv` sale `ERROR`. El log del
  partido muestra `net::ERR_NAME_NOT_RESOLVED` (a las 08:04 no había DNS/red); lo mismo
  les pasó a `UkWOzxk1`, `ld4AV1UI` y `xGZWYFJD`. No hay ningún CSV del partido en disco.
- Por qué parecía procesado: el proceso termina con «Proceso terminado» y código 0
  aunque haya errores, y el motivo guardado era la última línea del log
  (`(No symbol) [0x7ff…]`), que no dice nada.

## Backlog

- [x] 1. `pendientes/csv_faltan.py` (`basket csv-faltan [match_id]`): auditoría fresca y,
  por cada partido pendiente, qué datasets faltan, qué CSV hay en `competitions` y en
  `READY_DIR`, y el último estado/motivo en `PROCESAR_MATCHIDS_*.csv`. Escribe
  `CSV_FALTAN_<stamp>.csv` en `REPORT_DIR`. Solo lectura (salvo refrescar la auditoría).
- [x] 2. `procesar_matchids.py`: el motivo del error es la última línea con
  `Error`/`Exception` del log, no el último volcado de la pila.
- [ ] 3. Skill `.claude/skills/csv-faltan/SKILL.md`, tests, `basket verificar` en VERDE (pendiente: el worktree no tiene el submódulo `local-validation`; ejecutar en el checkout principal),
  evidencia en `docs/VERIFICACION-SDD.md`, commit + push.
