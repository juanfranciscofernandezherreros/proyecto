# Plan: `resultados-ayer` cuadra antes de extraer

## Objetivo

No perder tiempo extrayendo de Flashscore lo que ya está. Hoy `basket resultados-ayer`
extrae siempre las 11 ligas (unos 7 minutos), aunque los partidos de ayer ya estén en
Mongo con su marcador. Pedido por el usuario el 2026-11-17: comprobar primero, con el
cuadre diario, si ya están todos.

## Diseño

- Antes de extraer, **cuadre previo** con las funciones de `cuadrar_dia.py`:
  - fixtures: `leer_fixtures(dia)`, los partidos programados ese día.
  - Flashscore: si ya existe `RESULTS_YESTERDAY_<dia>.csv` (de una ejecución anterior),
    sus partidos; si no, nada (no se extrae para cuadrar).
  - Mongo: `leer_mongo(ids)` y `cuadrar(...)`.
- Un partido está **pendiente** si no está en Mongo, no tiene marcador o el marcador
  difiere del de Flashscore. Las secciones (jugadas, estadísticas) no cuentan: son de
  los pendientes, no de este comando.
- Decisión:
  - Hay partidos ese día y ninguno pendiente → `Ya están todos: n de n en Mongo con su
    marcador.`, no extrae ni carga, código 0.
  - Hay pendientes → extrae solo las ligas que los tienen; el resto del flujo igual.
  - fixtures no tiene partidos ese día → extrae todas (no se puede saber qué falta).
- `--forzar`: se salta el cuadre previo y extrae todas, como hasta ahora.
- Si el cuadre previo falla (Postgres o Mongo caídos), avisa y extrae todas.

## Backlog

- [x] 1. Este plan.
- [x] 2. `resultados_ayer.py`: función pura `ligas_pendientes(fixtures, flashscore, mongo)` y cuadre previo antes de extraer.
- [x] 3. Extraer solo las ligas con pendientes; sin pendientes, terminar con código 0.
- [x] 4. Opción `--forzar` (y ayuda de `basket`).
- [x] 5. Tests `ResultadosAyerCuadrePrevioTests` y gate `verificar.py` en verde. 45 tests OK.
- [x] 6. Prueba real con `/resultados-ayer` (16-nov ya cargado): debe decir que ya están los 8 sin extraer. Hecho el 17-nov 10:28: "Cuadre previo: 8 partidos; ligas con pendientes: ninguna", código 0, sin extraer.
- [x] 7. Skill `resultados-ayer`, evidencia en `docs\VERIFICACION-SDD.md` §17, commit + push.
