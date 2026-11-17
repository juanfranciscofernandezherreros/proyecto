# Plan: `resultados-ayer` sin gastar tokens

Fecha: 2026-11-17

## Objetivo

Que el resultado diario de `basket resultados-ayer` llegue sin pasar por Claude y que,
cuando sí se use la skill, gaste lo mínimo.

## Situación de partida

- Ya existe la tarea programada **"Basketball - Resultados de ayer al iniciar"**
  (al iniciar sesión, `basket resultados-ayer`; último resultado 0). No se toca. Ojo:
  "No iniciar en batería".
- El comando no avisa de cómo terminó: hay que mirar el log o preguntar a Claude.
- La skill tiene 4.700 caracteres de cuerpo, una descripción de 700 (cargada en cada
  mensaje de cada sesión) y no lleva `model: haiku`.

## Diseño

1. `resultados_ayer.py` acumula un resumen (día, partidos, cuántos en Mongo, ligas con
   fallo, error) y al terminar, salga por donde salga, imprime **una** línea
   `RESUMEN: …` y la manda al bot de Telegram (si está configurado; si falla, solo avisa):
   - `✅ Resultados de ayer 16/11 · ya estaban los 8 en Mongo`
   - `✅ Resultados de ayer 16/11 · 8 de 8 en Mongo`
   - `❌ Resultados de ayer 16/11 · 7 de 8 en Mongo · 1 liga con fallo`
   - `❌ Resultados de ayer 16/11 · ERROR: <motivo>`
2. Skill `resultados-ayer` fina: `model: haiku`, descripción < 200 caracteres, cuerpo de
   ~15 líneas: el comando, leer solo la línea `RESUMEN:` y qué hacer si sale ❌.

## Backlog

- [x] `resultados_ayer.py`: resumen acumulado, línea `RESUMEN:` y envío a Telegram.
- [x] Tests de la línea de resumen (los cuatro casos).
- [x] Prueba real: `basket resultados-ayer` (día ya cuadrado) imprime `RESUMEN:` y llega al bot.
- [x] Skill `resultados-ayer` fina (haiku, descripción corta, cuerpo corto).
- [x] Evidencia en `docs\VERIFICACION-SDD.md` y gate en verde.
- [x] Commit + push.
