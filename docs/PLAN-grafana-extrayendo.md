# Plan: «Extrayendo ahora» en el dashboard de pendientes

Pedido el 2026-11-18. El dashboard `fixtures-audit-live` (Partidos pendientes) no
muestra qué partido se está bajando de Flashscore. `basket resultados-ayer` /
`reextraer` no apuntan nada en `public.pipeline_step` (solo lo hace el orquestador de
ligas), así que ni siquiera el dashboard «Procesamiento en vivo» lo ve.

## Backlog

- [x] 1. `scripts/py/seguimiento.py`: `empezar(...)` / `terminar(...)` sobre
  `public.pipeline_step` vía `docker exec psql`, sin cortar nada si falla.
- [x] 2. `reextraer.py`: una fila por partido y dataset (`RUNNING` → `COMPLETED`/`FAILED`
  con el CSV o el motivo). Liga `pais/competicion`, paso `DATASET match_id`.
- [x] 3. Dashboard `csv-extra-batch/observability/fixtures-pending-dashboard.json`: panel
  arriba «Extrayendo ahora» (filas RUNNING de la última hora) y «Últimos pasos» (2 h).
- [ ] 4. Comprobar en Grafana con la extracción en marcha. Pendiente: el `resultados-ayer` que corre ahora usa el código de `main`; se verá en la próxima ejecución tras fusionar la rama. Dashboard ya publicado (versión 7) y escritura probada (id 374).
- [x] 5. Tests, evidencia, commit + push (repo y submódulo `csv-extra-batch`).
