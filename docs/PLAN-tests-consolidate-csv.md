# Plan: poner en verde `test_consolidate_csv.py` (python-pyppeter)

Fecha: 2026-11-20

## Problema

`python -m pytest -q tests` en `python-pyppeter` da 3 fallos, todos en
`tests/test_consolidate_csv.py`, con `FileNotFoundError: Match bundle does not exist`.

## Diagnóstico

- El commit `e6fc998` («Guardar cambios en curso», 2026-11-08) reescribió
  `consolidate_csv.py`: pasó de **consolidar una ejecución entera por competición**
  (`manifest.json`, `run.complete`, cambio atómico de `current`, `SCORE_SUMMARY_*_all.csv`)
  a **preparar los CSV de un solo partido** en `<output>/current/<match_id>/`.
- Los tests no se tocaron: siguen llamando a `consolidate(raw, ready, "<runId>")` y
  esperan un dict con `files`/`runId`. Es decir, **los tests están desfasados**; el
  código hace lo que espera el pipeline actual.
- Quien usa el contrato nuevo (`--match-id` obligatorio): `python\process_pending_match_csvs.py`
  (`basket pendientes`) y `python\run_match_pipeline.py`. Por tanto no se cambia el
  comportamiento de `consolidate_csv.py`.

Contrato actual que deben cubrir los tests:

1. `match_id` alfanumérico; si no, `ValueError`.
2. Debe existir `<input>/<match_id>/`; si no, `FileNotFoundError`.
3. `RESULTS_*.csv` se buscan en `<input>` (del más reciente al más antiguo por mtime) y
   se copia solo la fila del partido (`matchId` o `match_id`) del primero que la tenga.
4. Para el resto de prefijos se copia el CSV más reciente **con filas** de la carpeta
   del partido (se ignoran los que solo tienen cabecera).
5. `prefixes` limita qué se prepara; si no se copia nada, `RuntimeError`.

## Backlog

- [x] Reproducir los 3 fallos y diagnosticar (tests desfasados tras `e6fc998`).
- [x] Reescribir `tests/test_consolidate_csv.py` para el contrato actual (puntos 1-5).
- [x] `python -m pytest -q tests` en python-pyppeter: 0 fallos.
- [x] Commit + push del submódulo y del puntero en la raíz.
- [x] Evidencia en `docs/VERIFICACION-SDD.md` y `basket verificar` VERDE.

## Fuera de alcance (seguimiento)

`python\orchestrate_competition.py`, `python\ingest_competition_batch.py`,
`python\basketball_mcp_server.py` (`consolidate_competition`) y
`python-pyppeter\run_lega_a_pipeline.py` siguen llamando a `consolidate_csv.py` sin
`--match-id` (contrato antiguo por competición): con el código actual fallarían en
`argparse`. No se tocan aquí.
