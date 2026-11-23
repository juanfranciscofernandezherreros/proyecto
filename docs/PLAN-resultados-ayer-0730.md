# Plan: resultados de ayer a las 7:30, despertando el portátil

Pedido el 2026-11-23. Que el portátil se active a las 7:30 y lance
`basket resultados-ayer` (que ya encadena los pendientes). El apagado al terminar
**no hace falta** (lo descartó el usuario).

Situación de partida:
- Tarea activa «Basketball - Resultados de ayer al iniciar» (al iniciar sesión, +2 min).
  «Ciclo diario» (06:00, con WakeToRun) está deshabilitada.
- El portátil solo tiene Modern Standby (S0) e hibernación; no S3. Los temporizadores
  de activación están **deshabilitados** en el plan de energía (AC y batería = 0).
- Un equipo apagado del todo no lo enciende Windows: solo desde suspensión o
  hibernación (o con el encendido programado de la BIOS, si lo tiene).

## Backlog

- [x] 1. `scripts/py/arranque/tareas.py`: nueva tarea `resultados` [HH:mm] (por defecto
  07:30), «Basketball - Resultados de ayer por la manana» (sin «:», que schtasks no admite), trigger diario con `WakeToRun` y
  `StartWhenAvailable`, que lanza `basket resultados-ayer`, también con batería.
- [x] 2. Instalarla (`tareas.py resultados instalar 07:30`) y comprobar el XML con
  `schtasks /query /xml`. La de «al iniciar» se mantiene: si a las 7:30 ya está todo
  en Mongo, `resultados-ayer` termina sin extraer.
- [ ] 3. (Pendiente del usuario: ajuste del sistema que no hace Claude.) Temporizadores de activación: los activa el usuario (es un ajuste del sistema).
  Comando que se le da: `powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1`
  (y `setdcvalueindex` si quiere también con batería) + `powercfg /setactive SCHEME_CURRENT`.
- [x] 4. Documentar en `docs/ESPECIFICACIONES.md`, evidencia en `docs/VERIFICACION-SDD.md`,
  `basket verificar` en VERDE, commit + push.
