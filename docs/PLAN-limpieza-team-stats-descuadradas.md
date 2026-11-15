# Plan — Limpieza de las TEAM_STATS descuadradas

> **Fecha:** 2026-11-15 · **Relacionado:** [SDD.md](SDD.md) (§5.1 modelo de datos, §11
> riesgos), [PLAN-skill-auditar-datos.md](PLAN-skill-auditar-datos.md),
> [PLAN-basket-reextraer.md](PLAN-basket-reextraer.md). **Repo:** raíz. **Estado:** pausado (reextracción a medias, nada borrado).

## 1. Problema

El control 15 de la auditoría dio 7480 filas de `team_stats.team_stats` cuya métrica es un
valor (`50.0%`, `(2/2)`) en 262 partidos, cargadas con el scraper antiguo. Esos partidos no
tienen copia buena de los porcentajes de tiro, y además guardan los rebotes con categoría
`Scoring` en vez de `Rebounds`.

## 2. Solución

Reextraer TEAM_STATS de los 262 partidos con el scraper corregido (el batch hace UPSERT:
añade las filas buenas) y borrar después las filas antiguas que el UPSERT no pisa. El
borrado solo toca partidos que ya tienen la fila buena `Field goal %`.

## Backlog

- [x] Analizar las filas y confirmar que no hay copia buena (`sql\consultas\2026-11-15_1510_team-stats-descuadradas-sin-copia-buena.sql`)
- [x] Guardar la consulta de borrado antes de ejecutarla (`sql\consultas\2026-11-15_1525_limpiar-team-stats-descuadradas.sql`)
- [x] Probar la reextracción con un partido (`0bG6tX1t`) y ajustar el borrado a los rebotes duplicados
- [ ] Reextraer los 261 partidos restantes — **pausado por el usuario el 2026-11-15 a las 17:13**: 94 de 262 hechos, 0 fallos, quedan 168. Para retomar: sacar los pendientes (partidos con métrica-valor y sin `Field goal %`) y lanzar `basket reextraer --dataset equipo --fichero <lista>`
- [ ] Revisar los partidos que hayan fallado y reintentarlos con `basket reextraer --dataset equipo`
- [ ] Ejecutar el borrado (PASO 3) y anotar el resultado en la cabecera de la consulta
- [ ] Repetir la auditoría y comprobar que el control 15 queda a cero (o solo los fallidos)
- [ ] Anotar la evidencia en `VERIFICACION-SDD.md`
- [ ] Commit + push

## 3. Encaje con el SDD

- §4: no cambia el flujo; la reextracción usa scraper → CSV → launcher → Postgres.
- §5.1: corrige datos de `team_stats.team_stats`; el projector los reproyecta a Mongo solo.
- Regla `consultas-sql`: la escritura está guardada antes de ejecutarse.
