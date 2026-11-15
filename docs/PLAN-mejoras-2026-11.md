# Plan — Mejoras de noviembre de 2026 (fiabilidad de datos, vigilancia y calidad)

> **Fecha:** 2026-11-15 · **Relacionado:** [SDD.md](SDD.md) (§4 flujo, §5 modelo de datos,
> §6 interfaces, §11 riesgos, §13 verificación continua),
> [VERIFICACION-SDD.md](VERIFICACION-SDD.md). **Repos:** raíz, `csv-extra-batch`,
> `basketball-match-api`. **Estado:** en curso.

## 1. Origen

Lista ordenada acordada con el usuario el 2026-11-15, tras la auditoría de datos
(`PLAN-skill-auditar-datos.md`) y la limpieza de TEAM_STATS
(`PLAN-limpieza-team-stats-descuadradas.md`, pausada y **fuera** de este plan).

## Backlog

Un commit + push por paso. Cada paso se marca al quedar hecho y verificado.

- [ ] 1. Activar `CICLO_RESULTS=1` en `config\basketball.env`
- [x] 2. Validar la métrica en el batch de `team_stats` (`csv-extra-batch`): rechazar filas cuya métrica es un valor o cuyo valor no tiene dígitos — commit `67f684e`, 7 tests unitarios
- [x] 3. Reemplazar el partido al reimportar TEAM_STATS — hecho como paso `replaceStaleRows` del job: borra las filas antiguas de los periodos que trae el CSV nuevo y conserva los periodos que no trae (más prudente que borrar el partido entero). Commit `a14fcaf`, 4 tests de integración
- [x] 4. `basket reextraer` reanudable: opción `--progreso <fichero>` que anota OK o FALLO por partido y dataset y salta lo ya hecho
- [x] 5. Dos controles nuevos en la auditoría: 18 rebotes en categoría `Scoring` (3783 filas) y 19 métricas de tiro con valor sin `%` (831 filas en 167 partidos, 0 en partidos ya reextraídos)
- [x] 6. `basket auditar` y su ejecución al final del ciclo diario (el ciclo completo no se ha lanzado; se verá en el log de las 06:00)
- [x] 7. Arreglar los tests de la API que no compilan (`PLAN-ci-api-tests.md`) — **ya estaba hecho** (commit `35f2fd5` de la API); el plan seguía como "propuesto". Comprobado: `mvnw test`, 22 tests en verde. Solo se ha corregido el estado del plan
- [x] 8. Filtro `finished` de la API basado en el marcador, no en `result.eventTime` — commit `a0fb102` de la API, 23 tests. Entra en vigor al reconstruir la imagen de la API (el stack está parado)
- [ ] 9. Comprobar si los extractores existentes pasan la ruta del driver de Edge al scraper
- [ ] 10. Tests para `scripts\py` (catálogo de ligas, jornadas, argumentos de `reextraer`)
- [ ] 11. Trazabilidad: fecha de relanzamiento en el launcher y de actualización en jugadas y resumen
- [ ] 12. Limpieza: `python\`, carpetas con solo `target\`, referencias a `.ps1` en el SDD
- [ ] 13. Web: clasificación, calendario y página de jugador

## 2. Encaje con el SDD

- §4: ningún paso cambia el flujo CSV → launcher → Postgres → projector → Mongo → API → web
  ni los puertos.
- §5.1: los pasos 2, 3 y 5 protegen y vigilan las tablas fuente.
- §6: el paso 8 cambia el criterio de un filtro, no el contrato de la API.
- §11: los pasos 2 y 3 atacan la causa de los datos descuadrados; el 8, la de los
  partidos con marcador que no salen en la web.
- §13: los pasos 6, 7 y 10 refuerzan la verificación continua.

## 3. Notas por paso

Se rellenan al ejecutar cada paso (qué se cambió y cómo se verificó); la evidencia
completa va a `VERIFICACION-SDD.md`.
