# Plan: cuadrar cada día los partidos de Flashscore, fixtures y Mongo

## Objetivo

Comprobar cada día que los partidos de ayer son los mismos, y con el mismo marcador,
en Flashscore, en `fixtures.fixtures` (Postgres) y en `matches` (MongoDB, lo que enseña
la web), y que en Mongo tienen todas las secciones.

## Fuentes

| Fuente | De dónde |
|---|---|
| Flashscore | Último `RESULTS_*.csv` de cada liga del catálogo (`LIGAS_BASKET.json`) en `COMPETITIONS_DIR\<pais>\<competicion>\`: es la lista que publica Flashscore al extraer. Se avisa si el CSV es anterior al final del día comprobado (hay que extraer antes con `basket resultados ALL`). |
| fixtures | `fixtures.fixtures`, fecha local `Europe/Madrid` |
| Mongo | `basketball.matches` por `_id`: marcador de `result` y `availableSections` |

## Diseño

- `scripts\py\lanzadores\cuadrar_dia.py [AAAA-MM-DD]` (por defecto, ayer) y comando
  `basket cuadrar`.
- Función pura `cuadrar(flashscore, fixtures, mongo)` → lista de partidos con sus
  problemas (falta en una fuente, marcador distinto, secciones que faltan).
- Salida: una línea por partido, resumen y código 0 si todo cuadra, 1 si no.
- Skill `.claude\skills\cuadrar-partidos-dia\SKILL.md` que lo lanza, interpreta y dice
  qué hacer con cada problema; fila en `CLAUDE.md`.
- Ejecución diaria: tarea programada (se propone al usuario, no se crea sin su sí).

## Backlog

- [x] 1. Este plan.
- [x] 2. `cuadrar_dia.py` + comando `basket cuadrar`.
- [x] 3. Tests `CuadrarDiaTests` y gate `verificar.py` en verde.
- [x] 4. Skill `cuadrar-partidos-dia` y fila en `CLAUDE.md`.
- [x] 5. Prueba real con `2026-11-16` (debe salir 8 partidos, todo cuadra).
- [x] 6. Evidencia en `docs\VERIFICACION-SDD.md` (§16), commit + push.
- [x] 7. Programarlo cada día en `basket ciclo-diario` con este orden (pedido por el usuario): datos de ayer → cuadre → RESULTS → cuadre → pendientes.
