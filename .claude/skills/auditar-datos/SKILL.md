---
name: auditar-datos
description: Audita la integridad de los datos del proyecto Basketball en PostgreSQL con una sola consulta de solo lectura — duplicados, results sin hora, país o fecha, fechas futuras, marcadores incoherentes, partidos jugados sin resultado, slugs de competición que no coinciden, partidos sin jugadas o estadísticas, team stats descuadradas y cargas fallidas — y dice qué arregla cada problema. Usar cuando el usuario pida auditar o revisar la calidad de los datos, pregunte si los datos están bien o qué datos están mal, tras una extracción o un procesado de pendientes, o antes de dar por bueno un cambio en el scraper, los batches o el projector. Para un partido concreto usar diagnosticar-partido; para saber qué servicios están levantados, estado-del-sistema.
model: sonnet
effort: medium
---

# Auditar los datos

Solo lectura. Una única consulta, ya guardada, que mira las tablas fuente de
Postgres y cuenta las filas que rompen cada regla.

## 1. Ejecutar

Un solo comando; arranca Postgres si hace falta:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd auditar"
```

Por debajo ejecuta `sql\consultas\2026-11-15_1445_auditoria-datos.sql`. El ciclo
diario la lanza al final y deja el resultado en su log
(`C:\data\basketball\reports\orchestrator\ciclo-diario-<fecha>.log`).

Esa consulta ya está en `sql\consultas\`, así que no hay que volver a guardarla.
Si para profundizar se lanza cualquier otra consulta, esa sí se guarda antes como
fichero nuevo (regla `consultas-sql`).

## 2. Leer el resultado

El **PASO 1** es el resumen: una fila por control, con `afectados` (0 es lo bueno)
y `gravedad`:

- **ALTA**: el partido no sale en la web o sale con datos falsos.
- **MEDIA**: sale, pero incompleto o mal clasificado.
- **INFO**: no es un error por sí solo.

Los **PASOS 2–7** desglosan por liga los controles que más se repiten; si el
control está a cero no devuelven filas.

| Control | Qué significa | Arreglo |
|---|---|---|
| 01, 02 duplicados | Dos filas con el mismo `match_id` | No debería pasar: revisar el batch de importación |
| 03 results_sin_hora | El partido sale sin hora (y una API anterior al 2026-11-15 lo oculta) | `sql\consultas\2026-11-07_1830_results-sin-event-time-no-salen-en-web.sql` |
| 04, 05 sin país, competición o fecha | El partido cae fuera de los filtros | Skill `extraer-resultados` de esa liga |
| 06 results_fecha_futura | Año mal inferido | `sql\consultas\2026-11-04_0900_results-fecha-futura-ano-mal.sql` |
| 07, 08 empate o parciales que no suman | Marcador mal leído | `basket.cmd reextraer --dataset resumen <match_id>` |
| 09 fixtures_jugadas_sin_result | Partido jugado sin marcador (desglose en PASO 3) | Skill `extraer-resultados` o `resultados-todas-las-ligas` |
| 10 slug_distinto_fixture_result | Calendario y resultado con competición distinta (PASO 4) | `docs\PLAN-normalizacion-competiciones.md` y `sql\consultas\2026-11-08_0000_normalizar-competiciones-fixtures.sql` |
| 11 results_sin_fixture | INFO: se clasifica solo por el result | Nada |
| 12–14 sin jugadas o estadísticas | Falta detalle que la fuente sí publica (PASO 5) | Skill `procesar-pendientes` o `extraer-datos-partido` |
| 15 team_stats_metrica_invalida | Filas cuya métrica es un valor (`51.4%`, `(38/72)`), del scraper antiguo (PASO 6) | Primero `basket.cmd reextraer --dataset equipo --fichero <lista>` y después `sql\consultas\2026-11-15_1525_limpiar-team-stats-descuadradas.sql` |
| 16 stats_player_duplicados | Mismo jugador dos veces en un partido | `basket.cmd reextraer --dataset jugadores <match_id>` |
| 17 cargas_fallidas_7_dias | Cargas del launcher que no terminaron bien (PASO 7) | Mirar el error y reenviar (skill `procesar-pendientes`) |
| 18 team_stats_rebotes_en_scoring | Rebotes guardados con categoría `Scoring` (scraper antiguo) | `basket.cmd reextraer --dataset equipo <match_id>`; el batch borra solo las filas antiguas |
| 19 team_stats_tiro_sin_porcentaje | Métrica de tiro con etiqueta válida pero valor sin `%` (p. ej. `(8/16)`): descuadre que el 15 no ve | Igual que el 18 |

Los controles 15, 18 y 19 son el mismo problema visto de tres formas y se arreglan a
la vez reextrayendo el partido; no hace falta SQL de limpieza desde el 2026-11-15.

Matices para no dar falsas alarmas:

- **09** con partidos solo de hoy o de ayer es normal: falta la extracción diaria.
  Preocupa cuando `mas_antiguo` tiene varios días.
- **12–14** ya descuentan lo registrado en `dataset_unavailable` y los partidos de
  menos de un día. Lo que sale es detalle que falta de verdad.
- **11** es alto por diseño: hay ligas cargadas solo desde RESULTS.

## 3. Contarlo

Corto, y empezando por lo que está mal:

1. Los controles ALTA con afectados, con la liga y el número.
2. Los MEDIA con afectados.
3. Una línea con cuántos controles están a cero.
4. Para cada problema, el arreglo de la tabla.

No corregir nada por iniciativa propia: esta skill solo informa. Si el usuario
pide el arreglo y es una escritura en la base de datos, guardar antes la consulta
en `sql\consultas\` marcada `ESCRITURA`.

## Añadir un control

Editar `sql\consultas\2026-11-15_1445_auditoria-datos.sql`: un bloque más en el
`UNION ALL` del PASO 1 con el siguiente número, su línea en "QUÉ HACER DESPUÉS" de
la cabecera y su fila en la tabla de esta skill. Los nombres y tipos de columna
están en `sql\consultas\2026-11-15_1437_esquema-tablas-auditoria.sql`.
