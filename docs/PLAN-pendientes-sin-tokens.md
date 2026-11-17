# Plan: `pendientes` sin gastar tokens

Fecha: 2026-11-17 · Igual que `PLAN-resultados-ayer-sin-tokens.md`.

## Objetivo

Que `basket pendientes` diga cómo terminó en **una línea** que llega al bot, y que la
skill `procesar-pendientes`, cuando se use, gaste lo mínimo.

## Diseño

1. `matchids_pendientes.py` acumula: procesados, errores (del
   `PROCESAR_MATCHIDS_*.csv` de la ejecución), resultado de la comprobación en Mongo
   (en Mongo / con todas las secciones) y cuántos quedan (`pendingFixtures` de
   `AUDIT_URL/latest`). Al terminar imprime `RESUMEN: …` y lo manda al bot:
   - `✅ Pendientes · 42 procesados · 42 de 42 en Mongo (27 completos) · quedan 55`
   - `❌ Pendientes · 40 procesados · 2 con error · 39 de 40 en Mongo (25 completos) · quedan 57`
   - `✅ Pendientes · nada que procesar · quedan 0`
   - `❌ Pendientes · ERROR: <motivo>`
   Que falten secciones no es ❌ (pueden ser `NO_PUBLICADO`); sí lo son los errores y
   los que no llegan a Mongo.
2. Skill `procesar-pendientes` fina: descripción < 200 caracteres, cuerpo corto, leer
   solo `RESUMEN:`. Ya era `model: haiku`.
3. Tareas programadas: no se tocan (las de pendientes están deshabilitadas; activarlas
   es decisión del usuario).

## Backlog

- [ ] `matchids_pendientes.py`: resumen, línea `RESUMEN:` y envío a Telegram.
- [ ] Tests de la línea de resumen.
- [ ] Prueba real: `basket pendientes "" 1` imprime `RESUMEN:` y llega al bot.
- [ ] Skill `procesar-pendientes` fina.
- [ ] Evidencia en `docs\VERIFICACION-SDD.md` y gate en verde.
- [ ] Commit + push.

## Descripciones cortas en todas las skills

Las descripciones se cargan en cada mensaje de cada sesión. Se recortan a ~150
caracteres (qué hace + cuándo usarla, sin mencionar otras skills) y se pone
`model: haiku` a `aviso-telegram` y `cuadrar-partidos-dia`.

- [x] Descripciones recortadas en las skills de operación y desarrollo.
- [x] `model: haiku` en `aviso-telegram` y `cuadrar-partidos-dia`.
- [x] Medición antes / después y evidencia en `VERIFICACION-SDD.md`.
