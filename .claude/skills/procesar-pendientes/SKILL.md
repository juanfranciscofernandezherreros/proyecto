---
name: procesar-pendientes
description: Procesa los partidos pendientes del proyecto Basketball, es decir, los ya jugados a los que les falta algún dataset (resumen, jugada a jugada, estadísticas de equipo o de jugadores): comprueba results y fixtures, lanza la auditoría, extrae e importa lo que falta y explica lo que queda sin datos. Usar cuando el usuario pida procesar los pendientes, completar partidos, ponerse al día, lanzar el ciclo diario, o pregunte cuántos partidos faltan o por qué un partido sigue pendiente.
---

# Procesar los partidos pendientes

Un partido está pendiente cuando ya se jugó y le falta al menos un dataset. Lo
decide el módulo de auditoría (`csv-extra-batch\fixtures-processing-audit`,
http://localhost:8090/fixtures-processing-audit).

## 1. Comprobar que results y fixtures están al día

Solo lectura; requiere Postgres arrancado:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\COMPROBAR_RESULTS_FIXTURES.bat"
```

Si al final `a_revisar = 0`, todo está registrado. Si no, hay ligas con partidos
jugados sin resultado: ejecutar antes la skill `extraer-resultados` para esas
ligas. La explicación completa de cada columna está en
`sql\consultas\2026-11-03_1710_results-y-fixtures-listos-para-pendientes.sql`.

## 2. Ver cuántos pendientes hay

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\AUDITORIA_FIXTURES.bat"
```

Lanza una auditoría nueva, imprime `Fixtures`, `Elegibles` y `Pendientes`, y deja
la lista en
`C:\data\basketball\reports\orchestrator\FIXTURES_PROCESSING_AUDIT_PENDING_<fecha>.csv`
con los datasets que le faltan a cada partido. El último resultado también está en
http://localhost:8090/fixtures-processing-audit/latest.

## 3. Procesar

En segundo plano y con ruta completa: puede tardar horas si hay muchos partidos.

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\MATCHIDS_PENDIENTES.bat"
```

- Argumentos opcionales: `[csv_de_seleccion] [limite]`. El CSV limita el trabajo a
  los partidos de esa lista (por ejemplo, el `ligas-orquestar-pendientes-<fecha>.csv`
  que deja el orquestador cuando falla una liga). Para pasar solo un límite, el
  primer argumento va vacío: `MATCHIDS_PENDIENTES.bat "" 20`.
- Asegura antes `antibloqueo postgres auditoria launcher navegador`.
- Refresca la auditoría al empezar y después de cada partido, y procesa solo lo que
  sigue pendiente.
- Al terminar deja un CSV de resumen en `C:\data\basketball\reports\orchestrator\`.

El ciclo diario completo (lo que corre la tarea programada) es:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\CICLO_DIARIO.bat"
```

Hace tres cosas: extrae los resultados de todas las ligas solo si
`CICLO_RESULTS=1` en `config\basketball.env` (hoy está a `0`), lanza
`MATCHIDS_PENDIENTES` y archiva los CSV repetidos. Log en
`C:\data\basketball\reports\orchestrator\ciclo-diario-<fecha>.log`.

## 4. Verificar

Volver a lanzar el paso 2: `Pendientes` debe haber bajado. Y comprobar las cargas:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, exit_code, created_at FROM public.batch_launch_request ORDER BY created_at DESC LIMIT 15;"
```

## 5. Explicar lo que sigue pendiente

No todo pendiente es un fallo. Cuando un dataset se ha intentado y Flashscore no lo
tiene, se registra para no reprocesarlo en bucle:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT estado, dataset, count(*) AS partidos, max(last_seen) AS ultimo_intento FROM fixtures_processing_audit.dataset_unavailable GROUP BY estado, dataset ORDER BY estado, dataset;"
```

- `NO_PUBLICADO`: la fuente no ofrece ese dataset para ese partido.
- `VACIO`: la página existe pero no devolvió filas (`rows_found = 0`).

Para un partido concreto, filtrar por `match_id`; las columnas `reason`, `attempts`
y `source_url` dicen por qué y cuántas veces se intentó. Si un partido sigue
pendiente y **no** aparece en esta tabla, es un fallo real de extracción o de
importación: revisar el log y, para seguirlo de punta a punta, la skill
`diagnosticar-partido`.

## Notas

- Consultas relacionadas ya guardadas en `sql\consultas\`:
  `2026-11-03_1200_pendientes-que-se-repiten.sql`,
  `2026-11-03_1650_pendientes-completados-sin-datos.sql`,
  `2026-11-03_1815_registro-datasets-sin-datos.sql`.
- `MONITOR_PENDIENTES.bat` y `GRAFANA_PENDIENTES.bat` abren ventanas para una
  persona; no sirven para comprobar el estado desde aquí.
- Las consultas ejecutadas se guardan en `sql\consultas\` (regla `consultas-sql`).
