# Plan — Skill `auditar-datos` (auditoría de integridad de datos)

> **Fecha:** 2026-11-15 · **Relacionado:** [SDD.md](SDD.md) (§5 modelo de datos, §11
> riesgos, §13 verificación continua), [VERIFICACION-SDD.md](VERIFICACION-SDD.md).
> **Repo:** raíz (`basketball`). **Estado:** ejecutado.

## 1. Problema

Las comprobaciones de integridad de Postgres se hacen a mano y repartidas en varias
consultas de `sql\consultas\` (fixtures sin results, results sin hora, fechas futuras,
team stats descuadradas, cargas que no dejaron datos...). No hay un punto único que diga
"qué datos están mal ahora mismo", ni una skill que lo lance y lo interprete.

## 2. Solución

Una skill de **solo lectura** que ejecuta un único fichero SQL reutilizable y explica el
resultado, indicando para cada control la skill o la consulta que lo arregla.

## 3. Pasos

| Paso | Qué | Fichero | Verificación |
|---|---|---|---|
| 1 | Consulta de auditoría: un resumen con una fila por control (PASO 1) y el desglose de los controles que más se repiten (PASOS 2–6) | `sql\consultas\2026-11-15_1445_auditoria-datos.sql` (+ `2026-11-15_1437_esquema-tablas-auditoria.sql` con las consultas de esquema usadas para escribirla) | Se ejecuta sin errores contra Postgres y el resultado queda anotado en la cabecera |
| 2 | Skill `auditar-datos` | `.claude\skills\auditar-datos\SKILL.md` | Frontmatter válido; el comando de la skill es el mismo que se probó en el paso 1 |
| 3 | Enlazar la skill | `CLAUDE.md` (tabla), `diagnosticar-partido` ("Varios partidos a la vez"), `docs\VERIFICACION-SDD.md` | La skill aparece en la tabla de `CLAUDE.md` |

## 4. Encaje con el SDD

- §3.2 / §4: no cambia el flujo ni los puertos; la skill solo lee Postgres.
- §5.1: audita las tablas fuente (`fixtures`, `results`, `team_stats`, `stats_player`,
  `point_by_point`, `dataset_unavailable`, `batch_launch_request`).
- §11: da un control medible a los riesgos "results sin hora" y "results sin
  país/competición", y al plan pendiente de normalización de slugs.
- §13: complementa a `basket verificar` (que mira servicios y cadena) con calidad de datos.

## 5. Fuera de alcance

- No corrige nada: los arreglos son las consultas `ESCRITURA` ya guardadas o las skills
  de extracción.
- No audita MongoDB (el desfase Postgres → Mongo lo cubre `diagnosticar-partido`).
- No añade un comando `basket auditar` (posible paso posterior).
