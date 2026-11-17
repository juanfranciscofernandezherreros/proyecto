# Plan: `basket resultados-ayer` y el fichero RESULTS_YESTERDAY

## Objetivo

Separar "los resultados de ayer" de la extracción general de resultados. `basket
resultados ALL` guarda por liga todo lo que publica Flashscore (semanas de partidos) en
`RESULTS_<extraccion>_<pais>_<competicion>.csv`; no hay un fichero con solo los partidos
de un día. El usuario quiere uno propio, con nombre distinto, para diferenciar la
funcionalidad.

## Diseño

- `scripts\py\lanzadores\resultados_ayer.py [AAAA-MM-DD] [--sin-extraer]`, comando
  `basket resultados-ayer`. Por defecto, ayer en `Europe/Madrid`.
- Paso 1 (salvo `--sin-extraer`): `ligas_orquestar.py ALL results` (lo mismo que
  `basket resultados ALL`).
- Paso 2: del último `RESULTS_*.csv` de cada liga del catálogo, las filas cuyo
  `eventDatetime` cae en ese día (misma lógica que `cuadrar_dia.filas_del_dia`).
- Salida: `REPORTS_DIR\resultados-ayer\RESULTS_YESTERDAY_<AAAAMMDD>.csv` con las columnas
  del RESULTS más `country` y `competition` delante. Fuera de `competitions\` para que la
  importación de RESULTS (que busca `RESULTS_*.csv` por liga) no lo recoja.
- Resumen por liga en pantalla; código 0 si se escribe el fichero.

## Backlog

- [x] 1. Este plan.
- [x] 2. `resultados_ayer.py` + comando `basket resultados-ayer` (sin extraer: el usuario pidió que solo genere el CSV a partir de los RESULTS ya extraídos).
- [x] 3. Tests `ResultadosAyerTests` y gate `verificar.py` en verde.
- [x] 4. Prueba real `basket resultados-ayer 2026-11-16` (8 partidos: NBA 5, Winner 3).
- [x] 5. Skill `resultados-ayer` y fila en `CLAUDE.md`.
- [x] 6. Evidencia en `docs\VERIFICACION-SDD.md` (§17), commit + push.
