# Plan: la extracción de jugadas y estadísticas se cae por la consola cp1252

## Problema

Desde el 9-14 nov, en BSL, ACB, Lega A, LKL, GBL, BBL y LNB no entran jugada a jugada,
estadísticas de equipo ni de jugadores (los resúmenes sí). `_run_tee`
(`scripts\py\extraer\dataset.py`) lee la salida del scraper como UTF-8 con
`errors="replace"` y la reescribe con `sys.stdout.write` en una consola `cp1252`.
Un carácter no representable (`�`, letras turcas...) lanza `UnicodeEncodeError`,
el extractor sale con código 1 y el orquestador omite la importación.
Lo comparten `extraer\point_by_point.py`, `extraer\dataset.py` (equipo y jugadores).

## Solución

En `_run_tee`, escribir en pantalla con una función que nunca falle: si la consola no
puede codificar la línea, se escribe sustituyendo los caracteres (`errors="replace"`
con la codificación de la consola). El log sigue en UTF-8 íntegro.

## Backlog

- [x] 1. Este plan.
- [x] 2. `_run_tee` tolerante a la codificación de la consola + test `RunTeeTests` con stdout cp1252.
- [x] 3. Gate `scripts\py\verificar.py` en verde.
- [ ] 4. Relanzar `basket orquestar BSL datos 15` y comprobar cobertura por partido.
- [ ] 5. Relanzar ACB, LEGA_A, LKL, GBL, BBL, LNB.
- [ ] 6. Evidencia en `docs\VERIFICACION-SDD.md` (§15), commit + push.
