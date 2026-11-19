# Plan: fecha y hora de los partidos desfasadas en la web

Fecha: 2026-11-19

## Problema

La web (8083) muestra todos los partidos **una hora antes** de la hora real de Madrid
y, en los que empiezan entre las 00:00 y las 01:59 de Madrid, **el día anterior**.

Análisis de los 40 últimos partidos finalizados (`/api/v1/matches`, orden
`eventDatetime,desc`, consultas en `sql\consultas\2026-11-19_1000_*` y `_1010_*`):

| Capa | Valor (Besiktas–Real Madrid) | Estado |
|---|---|---|
| Postgres `results.event_datetime` (timestamptz) | `2026-11-18 17:00:00+00` | Bien (instante correcto) |
| Postgres `results.event_time` (hora Madrid) | `18:00:00` | Bien |
| Mongo / API `eventDatetime` | `"2026-11-18 17:00:00.0"` | **Mal: sin zona horaria** |
| Web `qo()` → `new Date(...)` | `18 nov, 17:00` | **Mal: toma UTC como hora local** |

- 40 de 40: hora una hora menos (UTC en lugar de Madrid).
- 2 de 40 (`0GolR8ad`, `QgwzkCi3`, 00:00 Madrid del 16/11): además, día anterior.
- En todo `results`: 67 partidos con el día desfasado.

## Causa

`PostgresMatchReader.string()` del projector convierte el `java.sql.Timestamp` con
`toString()`, que escribe la hora en la zona de la JVM (UTC) **sin offset**. La API pasa
la cadena tal cual y el navegador la interpreta como hora local.

## Solución

En el projector, guardar `eventDatetime` en ISO-8601 con zona (`Instant`,
`2026-11-18T17:00:00Z`): ordena igual como texto y `new Date()` lo convierte a la hora
local del navegador (Madrid → `18 nov, 18:00`). Subir `PROJECTION_VERSION` para que se
reproyecten todos los partidos ya guardados en Mongo. No hace falta tocar la API ni la
web.

## Backlog

- [x] Analizar las fechas de los 40 últimos partidos y localizar la causa
- [x] Projector: `event_datetime` a ISO-8601 UTC (`Instant`) + test (`726f5db`)
- [x] Projector: `PROJECTION_VERSION` v2 → v3 para reproyectar lo existente
- [x] Reconstruir el contenedor del projector y esperar la reproyección (3533/3533)
- [x] Comprobar en la API que `eventDatetime` acaba en `Z` y en la web la hora de Madrid
- [x] `basket verificar` en verde y evidencia en `docs/VERIFICACION-SDD.md`

## Fuera de alcance

- `fixtures.event_time` distinto de `results.event_time` en 2 partidos NBA
  (`z7LaAJJt`, `8KJ78clg`): horario previsto que cambió; la web no lo usa.
