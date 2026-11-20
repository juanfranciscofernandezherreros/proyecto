# Plan: puntos añadidos en la primera jugada de cada cuarto

Pedido el 2026-11-20 al preparar las consultas de curiosidades (rachas de puntos).

## Diagnóstico

- `point_by_point.point_by_point_event` tiene 2643 jugadas de 882 partidos en las que
  `home_points_added` / `away_points_added` no cuadran con la diferencia de marcador
  respecto a la jugada anterior; todas con `sequence = 1`. Ejemplo: `pxFIMqFt`,
  `4th Quarter`, seq 1 → `104-104` con `points_added` 104/104. Control: PASO 5 de
  `sql/consultas/2026-11-20_2300_curiosidades-jugada-a-jugada.sql`.
- Origen: `python-pyppeter/extract_flashscore_point_by_point.py::parse` empieza cada
  página (un cuarto) con `previous_home = previous_away = 0`, y
  `extract_flashscore_all_quarters.py` llama a `parse` cuarto a cuarto sin pasarle el
  marcador con que acabó el cuarto anterior.
- El batch (`csv-extra-batch`) solo copia el valor; el projector lo lee tal cual e
  incluye el jugada a jugada en el `sourceHash`, así que al corregir Postgres
  reproyecta solo el partido en el siguiente ciclo (no hace falta subir la versión).
- Efecto visible: `basketball-match-web/src/pages/MatchDetailPage.tsx` pinta «+104».
- No afecta a remontadas, cambios de líder ni empates (usan el marcador).

## Backlog

- [ ] 1. `parse(html, source_url, previous_score=(0, 0))`: la primera jugada se compara
  con el marcador al final del cuarto anterior; `extract_quarters_with_driver` lo
  arrastra entre cuartos. Test en `tests/test_match_parsers.py`.
- [ ] 2. Corregir lo ya cargado: `sql/consultas/2026-11-20_2400_corregir-points-added.sql`
  (ESCRITURA, guardado antes de ejecutar) con UPDATE que recalcula `*_points_added`
  como diferencia con la jugada anterior del partido (orden `quarter, sequence`) y la
  comprobación del PASO 5 → `points_added_mal = 0`.
- [ ] 3. Reproyección a Mongo (el projector la hace solo al cambiar el hash) y
  comprobar en la API/web que `pxFIMqFt` muestra +2/+3 al empezar el 4º cuarto.
- [ ] 4. Defensa en `MatchDetailPage.tsx`: no mostrar «+N» si N > 4.
- [ ] 5. Evidencia en `docs/VERIFICACION-SDD.md`, `basket verificar` en VERDE,
  commit + push.
