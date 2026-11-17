# Plan: dejar en el SDD y en el gate lo hecho el 2026-11-17

## Objetivo

Que todo lo de hoy esté descrito en `docs\SDD.md`, tenga evidencia en
`docs\VERIFICACION-SDD.md` y, lo que se pueda comprobar con el stack arrancado, lo
compruebe `basket verificar` (`scripts\py\verificar.py`) en verde/rojo.

Cambios de hoy: Postgres antes que Grafana (vistas SQL), `pendientes` hasta el
projector, aviso por Telegram de cada CSV, predicción de la jornada al bot, skill
`aviso-telegram`, skills autocontenidas y borrado de `estado-del-sistema`.

## Backlog

- [x] `SDD.md` §7 Operación: `resultados-ayer` y `pendientes` hasta el projector, `basket telegram`.
- [x] `SDD.md` §9 Observabilidad: aviso por Telegram (CSV y predicción), token fuera de git.
- [x] `SDD.md` §13: comprobaciones nuevas del gate.
- [x] `verificar.py` 6: vistas de Grafana presentes en Postgres.
- [x] `verificar.py` 7: si Telegram está configurado, un único vigilante en marcha y ningún CSV terminado sin avisar (más de 2 min).
- [x] `VERIFICACION-SDD.md`: §21 con el arreglo Grafana/Postgres, las comprobaciones nuevas y el borrado de la skill.
- [x] Gate en verde y commit + push.

## Segunda pasada (el usuario pide actualizar los SDD)

- [x] `VERIFICACION-SDD.md`: fecha, §1 Resumen con lo de hoy, §3 Conformidad, §5.bis (script Python y skills versionadas).
- [x] `SDD.md`: fecha y §11 Riesgos (token expuesto en el chat, enlace localhost en el bot).
- [x] `ESPECIFICACIONES.md`: §7.1 pendientes hasta el projector, §7.5 aviso por Telegram, §8 comprobaciones del gate, §9 mapa de scripts en `scripts\py`.
- [x] Commit + push.
