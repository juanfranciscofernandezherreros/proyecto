# Plan: flujo diario sin gastar tokens

Pedido el 2026-11-17. Que el día funcione sin Claude: resultados de ayer → pendientes,
con avisos a Telegram y logs en Grafana, lanzado por la tarea programada.

Situación de partida:
- La tarea programada activa es «Basketball - Resultados de ayer al iniciar» (estado
  Listo). «Ciclo diario» y «Procesamiento automatico al iniciar» están deshabilitadas.
- `resultados-ayer` termina sin lanzar los pendientes; hoy los lanzaba Claude a mano
  (regla de memoria) y enviaba a mano a Telegram el aviso de «faltan N».

## Backlog

- [x] 1. `resultados_ayer.py`: al terminar (salvo `--solo-csv` o
  `RESULTADOS_AYER_PENDIENTES=0`) lanza `matchids_pendientes.main([])` en el mismo
  proceso, aunque los resultados hayan fallado. El código de salida es el peor de los dos.
- [x] 2. Tarea programada: no se toca. «Resultados de ayer al iniciar» ya está activa
  y con el punto 1 cubre el día entero. «Ciclo diario» sigue deshabilitada para no
  duplicar. Se documenta en `docs/ESPECIFICACIONES.md`.
- [x] 3. `procesar_matchids.py`: tras la auditoría, si hay N > 0 partidos, envía a
  Telegram «⏳ Pendientes: N partidos por procesar (~N min)». Si falla Telegram,
  avisa y sigue.
- [ ] 4. Seguimiento sin Claude: el dashboard de logs ya se abre solo (commit fd1682d)
  y los RESUMEN ya llegan al bot. Se actualizan la skill `resultados-ayer` (incluye
  los pendientes) y la memoria (no relanzar pendientes tras resultados-ayer).
- [ ] 5. Tests, `basket verificar` en VERDE, evidencia en `docs/VERIFICACION-SDD.md`
  y commit + push.
