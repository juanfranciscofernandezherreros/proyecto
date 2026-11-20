# Verificación contra el SDD — Cierre de desarrollo

> **Fecha:** 2026-11-08 · **Actualizado:** 2026-11-17 · **Relacionado:** [SDD.md](SDD.md),
> [ESPECIFICACIONES.md](ESPECIFICACIONES.md),
> [PLAN-normalizacion-competiciones.md](PLAN-normalizacion-competiciones.md).
>
> **Propósito:** comprobar que lo que se ha cambiado es lo que se pretendía, trazando
> cada cambio a su área del SDD y a su evidencia de verificación. Es el documento de
> aceptación del desarrollo.

---

## 1. Resumen

Dos desarrollos funcionales y dos de mantenimiento, todos verificados:

| # | Cambio | Área SDD | Estado |
|---|---|---|---|
| D1 | SCORE_SUMMARY con identidad de partido | §5, §8 | ✅ Verificado |
| D2 | Normalización de competiciones (acb/super-league) | §5, §11, Plan | ✅ Verificado |
| D3 | Projector: regenerar documentos con `fixture` nula | §3.1, §11 | ✅ Verificado |
| M1 | Observabilidad: revivir exporters + consolidar dashboards | §9, §11 | ✅ Verificado |
| M2 | Limpieza de servicios/dashboards muertos (Kafka) | §3.1, §9 | ✅ Verificado |
| M3 | API: tests que no compilaban → verdes (CI) | §6, §13 | ✅ Verificado |
| M4 | python-pyppeter: suite en verde (CI) | §3.1, §5, §13 | ✅ Verificado |
| 19 | `basket pendientes` hasta el projector (comprueba Mongo) | §7 | ✅ Verificado (42 de 42 en Mongo) |
| 20 | Aviso por Telegram de cada CSV y de la predicción de la jornada | §9 | ✅ Verificado |
| 21 | Postgres antes que Grafana; gate con vistas de Grafana y Telegram | §7, §13 | ✅ Verificado |

El detalle de cada desarrollo posterior al 2026-11-08 está en su sección (§7 en adelante).

---

## 2. Matriz de trazabilidad (intención → cambio → evidencia)

### D1 · SCORE_SUMMARY con identidad de partido  (SDD §8)

**Intención (SDD §8 / §11):** un partido que entra solo por SCORE_SUMMARY no debe
quedar sin hora ni país/competición, para que la API lo marque `finished` y salga en
la web.

| Requisito | Cambio | Fichero / commit | Verificación | OK |
|---|---|---|---|---|
| SCORE_SUMMARY lleva los campos de RESULTS | Contrato ampliado | `python-pyppeter/csv_contracts.py` · `da8a86d` | 23 columnas en el contrato | ✅ |
| Capturar hora real del partido | Record `score_datetime` de `.duelParticipant__startTime` | `extract_flashscore_match_details.py` · `da8a86d` | Selector comprobado en vivo → "06.11.2026 20:45" | ✅ |
| Rellenar identidad por fila | `score_rows` rellena eventTime/eventDatetime/equipos/marcador/país/competición | `extract_flashscore_match_bundle.py` · `da8a86d` | Prueba funcional: ambas filas correctas, todo dentro del contrato | ✅ |
| Cargar en `results` sin romper formato antiguo | Cabecera ≥15 cols + mapear identidad | `csv-extra-batch/match-summary` (`ResultRow`, `CsvInput`, `ResultsWriter`) · `b52c2b1`, `655f0da` | `mvn` BUILD SUCCESS; INSERT probado en transacción (ROLLBACK) | ✅ |
| Propagación end-to-end | — | — | `juVOVk74`: country/competition vacíos → `europe`/`euroleague`, event_time `20:45` en results → Mongo → API | ✅ |

**Red de seguridad:** si el scrape de la hora fallara, backfill desde `fixtures`
(`sql/consultas/2026-11-07_1830_...`).

### D2 · Normalización de competiciones  (SDD §5, §11 + Plan)

**Intención (Plan §4):** una sola verdad para `(country, competition)`; que fixtures y
results usen el mismo slug canónico.

| Requisito (Plan) | Cambio | Fichero / commit | Verificación | OK |
|---|---|---|---|---|
| 5.1/5.4 Mapa canónico aplicado al cargar | `acb→liga-endesa`, `super-league→winner-league` | `csv-extra-batch/fixtures/FixturesCsvReader.java` · `92561ab` | Compila; normaliza aunque el fichero traiga slug crudo | ✅ |
| 5.6 Migración de datos existentes | UPDATE fixtures | `sql/consultas/2026-11-08_0000_...` · `cd1fdf1` | UPDATE 258 + 160; PASO 3 = 0 filas | ✅ |
| 5.5 Reproyección | Reinicio projector | — | Mongo: 0 docs con fixture.competition acb/super-league | ✅ |
| 5.7 Filtros de la web | — | — | `/api/v1/matches/filters` sin `acb`/`super-league` | ✅ |
| 5.8 Regresión (sin slug no canónico) | Consulta de control | `sql/consultas/2026-11-08_0000_...` | fixtures=0, results=0 | ✅ |
| Join fixture+result | — | — | `hpNRiY33`: fixture=`liga-endesa`, result=`liga-endesa` | ✅ |

**Pendiente (no bloqueante):** Plan 5.2/5.3 (que el scraper nombre el fichero de
fixtures con el slug canónico). Cubierto funcionalmente por 5.4 (normalización en el
batch); queda solo como limpieza de nombres.

### D3 · Projector: documentos con `fixture` nula  (SDD §3.1, §11)

**Intención:** un partido con fixture en PostgreSQL debe tener su objeto `fixture` en
el read model; había ~1308 docs con `availableSections:["fixture"]` pero sin objeto
`fixture` (scheduled sin equipos/fecha, no filtrables por liga).

| Requisito | Cambio | Fichero / commit | Verificación | OK |
|---|---|---|---|---|
| Diagnóstico | Docs obsoletos de un build anterior; `sourceHash` saltaba la regeneración | — | `p2fm1ZKa` regenerado → vuelve con `fixture` completo | ✅ |
| Fix durable | `PROJECTION_VERSION` en el `sourceHash` → bump invalida estados y reproyecta todo una vez | `basketball-match-projector` `MatchProjectionService` | Projector v2 recompilado y redesplegado | ✅ |
| Resultado | — | — | docs con `fixture` nula: **1308 → 0**; con objeto fixture 1744 → **3081** (= fixtures en PG) | ✅ |
| Impacto web | — | — | `scheduled` NBA en la API: **0 → 1068** | ✅ |
| Regresión | Check añadido al gate | `scripts/Verificar.ps1` | VERDE (incluye "ningún partido con fixture nula") | ✅ |

### M1 · Observabilidad  (SDD §9, §11)

**Intención:** que los dashboards vuelvan a actualizarse.

| Requisito | Cambio | Evidencia | OK |
|---|---|---|---|
| Exporters vivos | Reinicio de postgres/mongodb/cadvisor/blackbox/promtail | Prometheus: todos los targets `up`, ninguno `down` | ✅ |
| Logs en Loki | Reinicio Loki+promtail | Loki ingiere (labels container/service; streams presentes) | ✅ |
| Auditoría | — | `/fixtures-processing-audit/latest` → 200 | ✅ |
| Set oficial importado | Import vía API | 14 dashboards en Grafana, ninguno de Kafka | ✅ |

**Deuda abierta (SDD §11):** exporters con `restart: "no"` → conviene
`restart: unless-stopped` o `VIGILAR_SERVICIOS.bat`.

### M2 · Limpieza de servicios/dashboards muertos  (SDD §3.1, §9)

| Requisito | Cambio | Commit | Evidencia | OK |
|---|---|---|---|---|
| Quitar microservicios Kafka del compose | compose + anchors | `local-validation` `0e89dcd` | `docker compose config --services` = 5 reales | ✅ |
| Borrar dashboards muertos y paneles Kafka | 18 ficheros → set oficial | `0e89dcd` | Sin kafka/kafbat/schema-registry; global 22→19 paneles | ✅ |
| Importador coherente | Aserción dinámica | `0e89dcd` | Ya no exige 23 fijos | ✅ |

---

## 3. Conformidad con el SDD

- **§5 Modelo de datos:** `results` y `fixtures` comparten slug canónico; SCORE_SUMMARY
  respeta el contrato ampliado. ✅
- **§8 Identidad de partido:** implementada y propagada hasta la API. ✅
- **§4 Flujo:** sin cambios de arquitectura; los cambios viven en scraper, batch y
  datos, como describe el SDD. ✅
- **§9 Observabilidad:** fuentes de datos vivas y set de dashboards consolidado. ✅
- **§7 Operación (2026-11-17):** `resultados-ayer` y `pendientes` terminan en el
  projector y comprueban Mongo; Grafana arranca después de Postgres. ✅
- **§9 Observabilidad (2026-11-17):** aviso por Telegram de cada CSV (solo estado,
  nombre y hora) y de la predicción de la jornada; comprobado por el gate. ✅
- **§11 Riesgos:** D1 y D2 cierran dos riesgos listados; quedan abiertos el bug del
  projector con `fixture` nula y el `restart` de los exporters (documentados). ⚠️

## 4. Riesgos abiertos (seguimiento)

| Riesgo (SDD §11) | Estado |
|---|---|
| Projector no proyecta `fixture` cuando `event_time` es nulo (~1337 scheduled) | **Cerrado** (D3): eran docs obsoletos; `PROJECTION_VERSION` fuerza reproyección. 0 rotos |
| Exporters con `restart: "no"` | Abierto — mitigación propuesta |
| Scraper nombra fixtures con slug crudo (Plan 5.2/5.3) | Mitigado por 5.4; limpieza pendiente |

## 5. Trazabilidad de commits

| Repo | Commit | Contenido |
|---|---|---|
| `proyecto` (raíz) | `831e38a`, `cd1fdf1` | SDD, especificaciones, bats, consultas, plan, migración |
| `python-pyppeter` | `da8a86d` | Contrato + scraper (D1) |
| `batch` (csv-extra-batch) | `b52c2b1`, `655f0da`, `92561ab` | match-summary (D1) + fixtures (D2) |
| `local-validation` | `0e89dcd` | Limpieza compose/observabilidad (M1/M2) |

### M3 · API: tests que no compilaban  (SDD §6, §13)

**Intención:** CI de `basketball-match-api` en verde (los tests no compilaban por firmas
antiguas). Ver [PLAN-ci-api-tests.md](PLAN-ci-api-tests.md).

| Requisito | Cambio | Fichero / commit | Verificación | OK |
|---|---|---|---|---|
| Constructor con `MongoTemplate` | mock añadido | `MatchServiceImplTest` · `35f2fd5` | compila | ✅ |
| `searchMatches` 7 args + `MongoTemplate` | mock `count`/`find`, llamada con 7 args | `MatchServiceImplTest`, `MatchControllerTest` · `35f2fd5` | `mvn test` 22/22 verde | ✅ |
| Sin cambio de contrato | solo tests | — | gate `Verificar.ps1` VERDE | ✅ |

### M4 · python-pyppeter: suite en verde  (SDD §3.1, §5, §13)

**Intención:** CI de `python-pyppeter` en verde. Ver [PLAN-ci-python-tests.md](PLAN-ci-python-tests.md).

| Requisito | Cambio | Verificación | OK |
|---|---|---|---|
| Default de navegador real (edge) | tests de navegador actualizados | — | ✅ |
| Contrato con `event_datetime` (fixtures y results) | expectativas y datos de tests de contrato/validador alineados | — | ✅ |
| Tests de rutas POSIX | `skipUnless(os.name=='posix')` (corren en CI Linux) | — | ✅ |
| Suite | — | `unittest` local: **OK (346, skipped=3)** | ✅ |

## 5.bis Infraestructura de verificación (gates)

La verificación es ahora **ejecutable y automatizable**, no solo manual:

| Capa | Qué | Dónde | Cómo se usa |
|---|---|---|---|
| Script | Checks verde/rojo del SDD (7 grupos: web/API, slugs, filtros, join, Mongo, vistas de Grafana, Telegram) | `scripts/py/verificar.py` · `1_EJECUTAR/basket.cmd verificar` | Stack arrancado → exit 0/1 |
| Tests | Lógica pura de `scripts/py` | `tests/test_scripts_py.py` | `python -m unittest discover -s tests` |
| Hook | Compila/typechea antes del push | `<repo>/.githooks/pre-push` | `git config core.hooksPath .githooks` (una vez por repo) |
| CI | Build + tests en cada push/PR | `<repo>/.github/workflows/ci.yml` | Automático en GitHub |
| Skill | Normas + flujo SDD→plan→verificación | `/normas-basketball` | Invocar antes de implementar/revisar |

**Estado del CI:** `basketball-match-api` (M3) y `python-pyppeter` (M4) ya están **en
verde**. El resto de repos no tenían suites rotas. El gate cumple su función.

**Notas:** las skills, reglas, agentes y comandos de `.claude/` se versionan (solo se
ignora la configuración local de la máquina); el hook requiere activación manual por repo (diseño de git).

## 6. Conclusión

Lo implementado se corresponde con lo pretendido en el SDD y el plan: cada requisito
tiene cambio, fichero/commit y evidencia de verificación. Quedan tres riesgos abiertos,
documentados y con mitigación propuesta, ninguno bloqueante para lo entregado.

## 7. Migración de `.bat`/`.ps1` a Python (plan `PLAN-bat-a-python.md`)

Conversión por capas, con paridad de salida como criterio de aceptación. No altera el
flujo del SDD §4 ni los puertos.

| Paso | Qué | Verificación | OK |
|---|---|---|---|
| 0 | `config.ps1` → `scripts/py/config.py`; helper `proc.py`; `estado_lib.py` usa `config.py` | `diff` de `config.py` vs `config.ps1 -FormatoBat`: **sin diferencias**. Imports OK; `estado.py` exit 1 con stack parado (igual que `ESTADO.bat`) | ✅ |
| 1 | `Estado.ps1` → `estado_sys.py`; `Verificar.ps1` → `verificar.py`; `estado_lib.leer_estado` usa `estado_sys` (ya sin ESTADO.bat) | `estado_sys.py` con paridad de texto frente a `ESTADO.bat` (solo difieren datos en vivo entre ejecuciones). `verificar.py`: comprobaciones 1–4 y código de salida iguales a `VERIFICAR.bat`; la paridad VERDE completa requiere el stack arrancado. `verificar.py` además no se aborta cuando Mongo está caído (el `.ps1` sí) | ✅ |
| 2 | Arranque: `ASEGURAR_SERVICIOS.ps1`+`ASEGURAR.bat` → `arranque/asegurar.py` (psutil + docker + urllib); `MANTENER_DESPIERTO.ps1` → `arranque/mantener_despierto.py` (ctypes); `ACTUALIZAR_EDGEDRIVER.ps1` → `arranque/edgedriver.py` (ctypes版本+firma) | `asegurar.py docker postgres` da "ya estaba listo" idéntico a `ASEGURAR.bat` (solo CRLF difiere), sin args → mismo ERROR y código 1; detección de launcher/antibloqueo OK. `edgedriver.py`: "ya coincide" código 0; firma de msedgedriver verifica Microsoft (fail-closed). `mantener_despierto.py`: SetThreadExecutionState/SendInput OK | ✅ |
| 3 | Importadores a Postgres: `IMPORTAR_RESULTADOS_EUROLIGA_*.ps1` → `importar/resultados.py`; `IMPORTAR_RESULTADOS_TODAS.ps1` → `importar/resultados_todas.py`; `PROCESAR_{TEAM,PLAYER,POINT_BY_POINT}_*.ps1` → `importar/{team_stats,player_stats,point_by_point}.py` (+ núcleo `launcher.py`/`stats_common.py`) | `resultados.py` sobre el RESULTS de EUROLIGA: envío al launcher COMPLETED y verificación **110 de 110**, idempotente, código 0 (idéntico al `.ps1`). `resultados_todas.py EUROLIGA`: RESUMEN "1 OK, 0 con fallo", código 0. Los tres de stats: verificados por import y por reutilizar el mismo submit/verify ya probado (no re-ejecutados en vivo) | ✅ |
| 4 | Extractores del scraper: `PARTIDOS_YA_IMPORTADOS.ps1` → `extraer/ya_importados.py`; `EXTRAER_DATASET_PENDIENTE.ps1` → `extraer/dataset.py`; `EXTRAER_PLAY_BY_PLAY_PENDIENTE.ps1` → `extraer/play_by_play.py`; `EXTRAER_POINT_BY_POINT.bat` → `extraer/point_by_point.py` | `ya_importados.py` **idéntico** al `.ps1` en los 4 datasets (750/723/690/756 IDs). Los 4 extractores en la ruta "nada que extraer" (EUROLIGA, 0 pendientes): mensajes y código 0 iguales al original. La invocación real del scraper (flashscore.py) es fiel por revisión, no ejecutada en vivo para no abrir Edge | ✅ |
| 5 | Orquestadores de ligas: `ORQUESTAR_LIGAS.ps1` → `ligas/orquestar.py`; `EJECUTAR_LIGA_BASKET.ps1` → `ligas/ejecutar_liga.py` (+ `catalogo.py`, `matchday.py`); `EJECUTAR_TODAS_LAS_LIGAS.ps1` → `ligas/ejecutar_todas.py`; `PROCESAR_ULTIMOS_PARTIDOS_COMPLETO.ps1` → `ligas/ultimos_partidos.py` | Selección de ligas (11 en orden; EUROLIGA sola) y filtros igual que el `.ps1`. `matchday.ultima_jornada`: 110→10 filas en 3 fechas, cortando al repetirse un equipo. Seguimiento `pipeline_step` OK (esquema aplica, SELECT 1→1). Las rutas de scraping/import se delegan a los módulos Python ya probados (pasos 3–4); no re-ejecutadas en vivo para no abrir Edge | ✅ |
| 6 | Pendientes/monitor: `PROCESAR_MATCHIDS_PENDIENTES.ps1`→`pendientes/procesar_matchids.py`; `ARCHIVAR_CSV_REPETIDOS.ps1`→`pendientes/archivar_csv.py`; `FIXTURES_SIN_RESULTS.bat`→`pendientes/fixtures_sin_results.py`; `RECOLECTAR_CONSUMO.ps1`→`monitor/recolectar_consumo.py`; `VER_PENDIENTES_*`→`monitor/ver_pendientes.py`; `watch_csv_processing.ps1`→`monitor/watch_csv.py` | `fixtures_sin_results` **idéntico** al `.bat`. `archivar_csv` (simulación) idéntico: 7990 vigentes, 3864 a mover. `recolectar_consumo --una-vez`: 95 filas en monitoring, sin error. `ver_pendientes`/`watch_csv --una-vez` renderizan. `procesar_matchids`: auditoría+cola verificadas; pipeline por partido fiel, no en vivo (scrapea) | ✅ |
| 7 | Los 20 lanzadores de `1_EJECUTAR` → `scripts\py\lanzadores\*.py`; cada `.bat` queda como shim de una línea que llama al Python | Compilan los 20; shims verificados: `ESTADO.bat` (estado completo), `IDS_PARTIDOS_AYER.bat` (match_id de ayer), `COMPROBAR_RESULTS_FIXTURES.bat` (tabla real, arreglada la codificación de bytes del SQL), `VERIFICAR.bat` (ROJO con stack caído). Delegadores y menús envuelven módulos ya probados | ✅ |
| 8 | Programador de tareas (`TAREA_*` → `arranque/tareas.py` vía schtasks/XML) y limpieza: borrados todos los `.ps1`/`.bat` reemplazados; `asegurar.py` repuntado a watcher/consumo Python; skills/CLAUDE.md actualizados | Las tareas ya registradas apuntan a los shims de `1_EJECUTAR` y siguen operativas (confirmada "Basketball - Ciclo diario"). `tareas.py estado` OK. Tras borrar: `ESTADO.bat` y `asegurar docker postgres` OK, todo `scripts\py` compila. Cero `.ps1`/`.bat` del pipeline fuera de `1_EJECUTAR` (shims) y `scripts\py`. Quedan solo `.ps1` de terceros (node_modules, .venv, hooks CI) y backups en `_archivo` | ✅ |

**Resultado de la migración:** el pipeline activo (CSV → launcher → Postgres → projector → Mongo → API → web) corre íntegramente en Python, sin PowerShell. Puertos y flujo del SDD §4 intactos.

## 8.bis Consolidación en el CLI `basket`

Los 20 `.bat` de `1_EJECUTAR` se sustituyen por un CLI único `basket` (`scripts\py\basket.py`)
con subcomandos coherentes, más `1_EJECUTAR\basket.cmd` como punto de entrada de Windows
(doble clic = menú). Verificado: `basket estado` y `basket procesar-csv EUROLIGA` (cadena
completa, 110 OK, idempotente); la tarea programada "Basketball - Ciclo diario" re-registrada
a `basket.cmd ciclo-diario` a las 06:00; 23 ficheros de docs/skills/SQL actualizados a
`basket.cmd <comando>`; todo `scripts\py` compila.

## 9. Skill `auditar-datos` (plan `PLAN-skill-auditar-datos.md`)

Auditoría de integridad de solo lectura sobre las tablas fuente de Postgres (SDD §5.1).
No altera el flujo del SDD §4 ni los puertos.

| Paso | Qué | Verificación | OK |
|---|---|---|---|
| 1 | `sql\consultas\2026-11-15_1445_auditoria-datos.sql`: 17 controles en un resumen (PASO 1) y 6 desgloses (PASOS 2–7) | Ejecutada el 2026-11-15 con `ON_ERROR_STOP=1`, sin errores. 10 controles a cero; con afectados: 09 = 30 (jornada del 14–15 nov sin RESULTS), 12/13/14 = 24/24/25, 15 = 7480 filas en 262 partidos, 17 = 1. El control 15 cuadra con el recuento independiente por etiqueta (47385 filas − 39905 de las 13 etiquetas reales = 7480) | ✅ |
| 2 | Skill `.claude\skills\auditar-datos\SKILL.md` | Lanza el mismo comando probado en el paso 1; cada control remite a la skill o consulta que lo arregla | ✅ |
| 3 | Enlaces: tabla de `CLAUDE.md` y skill `diagnosticar-partido` | Presentes | ✅ |

No se ha ejecutado `basket verificar`: exige web, API y Mongo levantados y este cambio no
toca código ni servicios (solo se arrancó Postgres para probar la consulta).

## 10. Comando `basket reextraer` (plan `PLAN-basket-reextraer.md`)

Reextrae y reimporta partidos concretos aunque ya estén importados. Usa el mismo camino
scraper → CSV → launcher → Postgres (SDD §4); sin puertos ni servicios nuevos.

| Paso | Qué | Verificación | OK |
|---|---|---|---|
| 1 | `scripts\py\extraer\reextraer.py` | `basket.cmd reextraer juVOVk74` (2026-11-15): `RESUMEN: 4 OK, 0 con fallo`, código 0. En Postgres, `team_stats` (60 filas) y `stats_player` (23) con `updated_at` de hoy y el mismo número de filas que antes (idempotente); `point_by_point` 83 y `match_summary` 1, sin cambio de recuento (esas tablas no tienen `updated_at`, así que ahí solo consta el `COMPLETED` del launcher) | ✅ |
| 2 | Lanzador `lanzadores\reextraer.py` y alta en `basket.py` | `basket ayuda` lo lista. Sin argumentos, con id inválido, con dataset inválido y con un id que no existe: mensaje claro y código 1 | ✅ |
| 3 | Documentación: `ESPECIFICACIONES.md` §6.1, skills `extraer-datos-partido`, `diagnosticar-partido` y `auditar-datos` | Referencias presentes | ✅ |

El mismo núcleo (resolvedor + `match bundle` + launcher) es el que está reextrayendo las
TEAM_STATS de 262 partidos el 2026-11-15. No se ha ejecutado `basket verificar` (web, API y
Mongo parados). Además se añade la regla `.claude\rules\backlog-de-pasos.md`.

## 11. Mejoras de noviembre de 2026 (plan `PLAN-mejoras-2026-11.md`)

Evidencia por paso. Ningún paso cambia el flujo del SDD §4 ni los puertos.

| Paso | Qué | Verificación | OK |
|---|---|---|---|
| 1 | `CICLO_RESULTS=1` en `config\basketball.env` | `scripts\py\config.py` lo lee como `1`. No se ha lanzado el ciclo: el efecto se verá en la ejecución programada de las 06:00 | ✅ |
| 2 | `csv-extra-batch/team-stats`: `TeamStatsRow.rejection()` rechaza filas cuya métrica es un valor (`51.4%`, `(38/72)`) o cuyo valor no tiene dígitos (commit `67f684e`) | `mvn -pl team-stats -am test`: 7 tests, 0 fallos (2 nuevos). Consulta previa `sql\consultas\2026-11-15_1730_team-stats-valores-sin-digitos.sql`: ninguna fila buena de las 47385 incumple la regla | ✅ |
| 3 | `csv-extra-batch/team-stats`: paso `replaceStaleRows` del job; borra las filas antiguas del mismo partido y periodo que el CSV nuevo no ha escrito (commit `a14fcaf`). Corregido el IT del JAR, que buscaba `target/app.jar` | `mvn -pl team-stats -am verify`: 7 unitarios + 4 de integración (Testcontainers), 0 fallos. Extremo a extremo: `basket.cmd reextraer --dataset equipo 04Lm2Xkm` dejó el partido en 65 filas (antes 80: 30 con métrica-valor y 15 rebotes duplicados en `Scoring`), 0 descuadradas, un único `source_event_id`, sin SQL manual | ✅ |
| 4 | `basket reextraer --progreso <fichero>` (`scripts\py\extraer\reextraer.py`) | Primera pasada con un partido real y uno inexistente: `1 OK, 1 con fallo`, fichero con una línea `OK` y otra `FALLO`. Segunda pasada con el mismo fichero: "1 partidos ya completos; se saltan", 0 extracciones, código 0. `--progreso` sin valor: error y código 1 | ✅ |
| 5 | Controles 18 (`team_stats_rebotes_en_scoring`) y 19 (`team_stats_tiro_sin_porcentaje`) en `sql\consultas\2026-11-15_1445_auditoria-datos.sql` | Auditoría ejecutada con `ON_ERROR_STOP=1`: 19 filas de control. 18 = 3783 filas, 19 = 831 filas en 167 partidos; el 19 da 0 en los partidos ya reextraídos (sin falsos positivos) | ✅ |
| 6 | `basket auditar` (`scripts\py\lanzadores\auditar.py`) y llamada al final de `ciclo_diario.py` | `basket.cmd auditar`: imprime los 19 controles y los desgloses, código 0; aparece en `basket ayuda`. `ciclo_diario.py` compila; el ciclo completo no se ha lanzado (extrae las 11 ligas), así que la llamada dentro del ciclo queda verificada solo por lectura | ✅ |
| 7 | Tests de la API | Ya estaban arreglados (commit `35f2fd5` de `basketball-match-api`); `PLAN-ci-api-tests.md` seguía como "propuesto" y se ha corregido. `./mvnw test` el 2026-11-15: 22 tests, 0 fallos | ✅ |
| 8 | `MatchServiceImpl.searchMatches`: `status=finished` exige solo `result.homeScore` y `result.awayScore` (commit `a0fb102`) | `./mvnw test`: 23 tests, 0 fallos; test nuevo que captura la consulta y comprueba que no incluye `result.eventTime`. No verificado contra la API desplegada: el stack está parado y la imagen hay que reconstruirla | ✅ |
| 9 | `scripts\py\config.py`: `cargar()` exporta `FLASHSCORE_BROWSER` y `EDGEDRIVER_PATH` al entorno | Misma llamada que `extraer\dataset.py` (subproceso a `flashscore.py match bundle` sin `env`): sin la exportación, código 1 con el error `driver_location` de Selenium; tras `config.cargar()`, código 0. Era un fallo real de los extractores de `scripts\py` desde la migración a Python (los pendientes no lo sufrían porque `python\proyecto_config.py` sí exporta). No se ha relanzado `basket orquestar` completo | ✅ |
| 10 | `tests\test_scripts_py.py`: jornadas (`matchday`), límites (`proc`), catálogo de ligas y `LIGAS_BASKET.json`, argumentos y progreso de `reextraer`, exportación del driver en `config` | `python -m unittest discover -s tests`: 18 tests, 0 fallos (16 nuevos + 2 que ya había). Solo lógica pura: no cubren importadores, launcher ni scraper | ✅ |
| 12 | Limpieza: `SDD.md` sin referencias a `.ps1`/`.bat` desaparecidos; borradas dos carpetas vacías (`csv-stats-player-batch`, `real-time-basketball-stats`: 0 ficheros, fuera de git). `python\` se conserva: está en uso | `grep` en `SDD.md`: solo queda `Start-BasketballLocal.ps1`, que existe en `local-validation\scripts`. Recuento de referencias a cada fichero de `python\` anotado en el plan | ✅ |
| 11 | Trazabilidad de relanzamientos | Sin cambio de código: ya existía. `batch_launch_request` de `juVOVk74`: `created_at` del 7-nov, pero `started_at`/`finished_at` del 15-nov y `attempts` = 3 tras la reextracción; las jugadas tienen `point_by_point_import` (`updated_at`, `completed_at`). Esto confirma además que en la prueba del §10 el `POINT_BY_POINT` sí se volvió a ejecutar. Corregidas 4 skills para ordenar por `finished_at` y mostrar `attempts` | ✅ |

## 12. Página de jugador (plan `PLAN-pagina-jugador.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | API: `PlayerPerformanceResponse` con `eventDatetime`, `competition`, `teamScore`, `opponentScore` (opcionales) | `./mvnw verify` en `basketball-match-api`: 32 tests, cobertura de líneas 82,14 % (umbral 80 %). Tests nuevos en `MatchServiceImplTest` (partido con datos y partido ausente) | ✅ |
| 2 | API: cobertura de `PostgresProcessingStatusProvider` (pendientes, relanzamiento, lectura de CSV) | 9 tests en `PostgresProcessingStatusProviderTest`; la cobertura del conjunto pasa de 61,5 % a 82,14 % | ✅ |
| 3 | Web: `utils/playerSummary.ts` (promedios, porcentajes acumulados, mejores marcas) | `playerSummary.test.ts`: 8 tests | ✅ |
| 4 | Web: resumen e historial en `PlayerPerformancesPage.tsx`, ordenado por fecha | Comprobado en `/performances/Wembanyama%20V.`: 12 partidos, promedio de puntos 25,7 = 308 / 12 | ✅ |
| 5 | Web: nombre del jugador enlazado desde `MatchDetailPage.tsx` | `typecheck` y `npm test` (31 tests) en verde | ✅ |
| 6 | Hallazgo: `teamScore`/`opponentScore` casi siempre `null` | Los jugadores llevan la abreviatura del equipo (`DAL`, `BRE`...) y el resultado el nombre completo. De 200 actuaciones, 2 con marcador (BBL). Pendiente de decidir (ver plan, §3b) | ⚠️ Abierto |

## 13. Skill `pronostico-jornada` (plan `PLAN-skill-pronostico-jornada.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | Consulta `sql\consultas\2026-11-15_2330_previa-jornada-datos.sql` (calendario próximo y forma de cada equipo, en JSON) | Ejecutada por `basket pronostico datos`: 30 partidos próximos, 20 equipos, 110 resultados de Euroliga | ✅ |
| 2 | `scripts\py\pronostico\previa.py` y lanzador `basket pronostico datos \| publicar` | `basket pronostico datos` da para la jornada 12 las mismas diez probabilidades calculadas a mano (Zalgiris 89,0 %, Valencia 56,8 %...) | ✅ |
| 3 | Tests de la lógica pura (`PronosticoPreviaTests`) | `python -m unittest discover -s tests`: 24 tests, 0 fallos (6 nuevos) | ✅ |
| 4 | `publicar` valida y no duplica | Borrador sin textos: lista lo que falta y no publica. Borrador relleno: "Artículo actualizado: euroliga-jornada-12-2026-11-15"; la colección sigue con 4 documentos y el publicado no lleva claves `_ayuda` | ✅ |
| 5 | Skill `.claude\skills\pronostico-jornada\SKILL.md` y fila en `CLAUDE.md` | Artículo visible en `http://localhost:8083/predictions/euroliga-jornada-12-2026-11-15` | ✅ |

## 14. `basket datos-ayer` y paso previo de los pendientes (plan `PLAN-resultados-por-fixtures.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | Consulta `sql\consultas\2026-11-17_0905_partidos-ayer-fixtures-vs-results.sql` | Antes de `basket resultados ALL`: 8 partidos de `fixtures` del 16/11 (Israel 3, NBA 5), los 8 sin resultado. Después: los 8 con marcador (p. ej. Boston 131-94 Dallas) | ✅ |
| 2 | Lanzador `scripts\py\lanzadores\datos_ayer.py` y comando `basket datos-ayer [AAAA-MM-DD]` | `basket ayuda` lo lista; con `2026-11-16` lee 8 `match_id` de `fixtures` y lanza `reextraer` con progreso reanudable | ✅ |
| 3 | Paso previo en `matchids_pendientes.py` (lo usan `pendientes`, `ciclo-diario`, `inicio-automatico`, `extraer-todo`), desactivable con `DATOS_AYER=0` / `SKIP_DATOS_AYER=1` | Sintaxis comprobada y 4 tests de `activo()`. **No ejecutado de extremo a extremo** (un `basket pendientes` completo no se ha lanzado) | ⚠️ |
| 4 | Tests (`DatosAyerTests`) | `python -m unittest tests.test_scripts_py`: 30 tests, 0 fallos (6 nuevos) | ✅ |
| 5 | Prueba real `basket datos-ayer 2026-11-16` | En curso al cerrar esta nota: partido `0GolR8ad` con los 4 datasets OK (equipo, jugadores, resumen, jugada a jugada); quedan 7 partidos. ~1,5 min por dataset | ⏳ |
| 6 | Gate `basket verificar` | VERDE (7 comprobaciones). Antes salía ROJO por web, API y Mongo parados; se arrancaron con `basket arrancar` | ✅ |

## 16. Cuadre diario Flashscore / fixtures / Mongo (plan `PLAN-skill-cuadrar-dia.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | `scripts\py\lanzadores\cuadrar_dia.py` y comando `basket cuadrar [AAAA-MM-DD]` | `basket cuadrar 2026-11-16`: Flashscore 8, fixtures 8, Mongo 8; 8 cuadran (NBA 5, Winner League 3), `TODO CUADRA`, código 0. Coincide con la comprobación a mano en flashscore.com de las 11 ligas | ✅ |
| 2 | Tests `CuadrarDiaTests` (fecha de Madrid, todo cuadra, cada tipo de problema, fecha) | `python -m unittest tests.test_scripts_py`: 36 tests, 0 fallos (4 nuevos) | ✅ |
| 3 | Skill `.claude\skills\cuadrar-partidos-dia\SKILL.md` y fila en `CLAUDE.md` | Gate `verificar.py` VERDE (7 comprobaciones) | ✅ |
| 4 | Ejecución diaria: paso de `ciclo_diario.py` (ver fila 5), tras 90 s de espera al projector (`CICLO_ESPERA_CUADRE`); un fallo del cuadre se anota como AVISO y no cambia el código del ciclo | Paso probado aislado sobre un log temporal: rc 0, `TODO CUADRA`; 36 tests y gate VERDE. Ciclo completo no ejecutado | ✅ |
| 5 | Orden del ciclo diario (pedido por el usuario): datos de ayer → cuadre → RESULTS → cuadre → pendientes (con `SKIP_DATOS_AYER=1`, ya hechos) → archivado → auditoría. Se quita el cuadre del final | Sintaxis OK; con `SKIP_DATOS_AYER=1`, `datos_ayer.activo()` da False; `_cuadre()` sobre un log temporal: `TODO CUADRA`; 36 tests y gate VERDE. Ciclo completo no ejecutado | ✅ |

## 17. `basket resultados-ayer` y RESULTS_YESTERDAY (plan `PLAN-resultados-ayer.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | `scripts\py\lanzadores\resultados_ayer.py` y comando `basket resultados-ayer [AAAA-MM-DD]`: no extrae, filtra el último RESULTS de cada liga y escribe `REPORTS_DIR\resultados-ayer\RESULTS_YESTERDAY_<AAAAMMDD>.csv` | `basket resultados-ayer 2026-11-16`: 8 partidos (NBA 5, WINNER 3) en `RESULTS_YESTERDAY_20261116.csv`, los mismos del cuadre | ✅ |
| 2 | Test `ResultadosAyerTests` | 37 tests, 0 fallos; gate `verificar.py` VERDE | ✅ |
| 3 | Skill `.claude\skills\resultados-ayer\SKILL.md` y fila en `CLAUDE.md` | Skill listada en la sesión | ✅ |
| 4 | Sin opciones lo hace todo: CSV → Postgres (launcher, por liga) → projector → comprobación en Mongo; tarea "Basketball - Resultados de ayer al iniciar" (al iniciar sesión) y desactivadas las otras dos de inicio | `basket resultados-ayer` (16-nov): winner-league 3 y nba 5 → COMPLETED; tras 90 s, 8 de 8 en Mongo con su marcador; 37 tests OK | ✅ |
| 5 | Extrae de Flashscore cada liga (python-pyppeter), asegura también el runtime (Mongo, projector) y da por fallida una liga a los 3 min de carga | `basket resultados-ayer` (17-nov, 16-nov): 11 ligas extraídas, winner-league 3 y nba 5 → COMPLETED, 8 de 8 en Mongo, código 0 | ✅ |
| 6 | Cuadre previo con la lógica de `cuadrar_dia` (fixtures / Mongo): si ya están todos no extrae; si no, solo las ligas con pendientes; `--forzar` extrae todas (plan `PLAN-resultados-ayer-cuadre-previo.md`) | `basket resultados-ayer` (17-nov 10:28, día 16): 8 partidos, ninguna liga con pendientes, código 0 sin extraer; 45 tests OK (`ResultadosAyerCuadrePrevioTests`); gate VERDE | ✅ |

## 18. Logs de `basket` en Grafana (plan `PLAN-logs-basket-en-grafana.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | `basket.py` duplica la salida de cada comando en `DATA_DIR\logs\basket\<comando>_<AAAAMMDD_HHMMSS>.log` y, salvo en `estado`/`vigilar`/`monitor`/`antibloqueo`/`grafana`, asegura Grafana y promtail e imprime el enlace `Logs en vivo:` | `basket resultados-ayer`: `Log:` y `Logs en vivo:` impresos; fichero `resultados-ayer_20261117_101025.log` | ✅ |
| 2 | promtail: job `basket` con etiquetas `comando` y `ejecucion`, `DATA_DIR\logs` montado en `/var/log/basketball`; servicio `promtail` en `asegurar.py` (lo recrea si falta el montaje) | Loki devuelve `comando=ids-ayer, resultados-ayer`; local-validation `e9fd53f` | ✅ |
| 3 | Dashboard `basket-logs` (Loki): filtros comando/ejecución/texto, líneas, fallos, líneas por minuto, fallos y avisos, salida en vivo | Visto en vivo en http://localhost:8084/d/basket-logs durante la ejecución, 0 fallos | ✅ |
| 4 | Loki 192→768 MB y promtail 96→256 MB (`Start-BasketballLocal.ps1`, `asegurar.py`): sin memoria, Loki no aceptaba envíos | Tras el cambio, Loki 110 MB y promtail 53 MB, CPU ~1 %; 53 de 56 líneas en Loki al momento | ✅ |
| 5 | Tests `BasketLogsTests` (regex de promtail, comandos sin Grafana, dashboard válido) | 42 tests OK; gate `verificar.py` VERDE | ✅ |
| 6 | `basket.py` abre por defecto en el navegador el dashboard `basket-logs` (enlace `Logs en vivo:`), salvo en `ciclo-diario`&`inicio-automatico` o con `BASKET_NO_ABRIR_GRAFANA=1` | Tests `test_abre_dashboard_de_logs_por_defecto` y `test_no_abre_en_tareas_programadas_ni_con_variable` (61 OK); `basket verificar` VERDE el 17&11 | ✅ |
| 7 | El dashboard `basket-logs` se abre siempre, también en `ciclo-diario` e `inicio-automatico`; solo `BASKET_NO_ABRIR_GRAFANA=1` lo evita | Test `test_abre_tambien_en_tareas_programadas` (62 OK); `basket verificar` VERDE el 17/11 | ✅ |

## 19. `basket pendientes` hasta el projector (plan `PLAN-pendientes-hasta-projector.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | `matchids_pendientes.py` asegura también `runtime` (Mongo, projector, API y web), como `resultados-ayer`; Grafana, Loki y promtail ya los levanta `basket.py` | Compila; gate `verificar.py` VERDE (17-nov) | ✅ |
| 2 | Al terminar, espera `CICLO_ESPERA_CUADRE` y comprueba en Mongo cada partido `COMPLETED` del `PROCESAR_MATCHIDS_*.csv` de la ejecución: `OK` / `FALTAN <secciones>` / `NO ESTA EN MONGO`; código 1 solo si alguno no está | Prueba con 6 partidos reales de liga-endesa y 1 inventado: 4 OK, 2 FALTAN, 1 NO ESTA EN MONGO → `ausentes: 1`; sin CSV de la ejecución, "No hay partidos procesados" | ✅ |
| 3 | Skill `procesar-pendientes` con la misma estructura que `resultados-ayer` (comando, pasos en orden, qué decir al terminar, tabla de fallos) y sin mandar a otras skills; ayuda de `basket pendientes` actualizada | Revisada a mano | ✅ |
| 4 | Comprobación en Mongo de una ejecución real de `basket pendientes` | Ejecución del 17-nov parada a petición tras el partido 42 de 97 (auditoría: quedan 55). `comprobar_en_mongo` sobre los 42: **42 de 42 en Mongo, 27 con todas las secciones**, 15 `FALTAN players`, los 15 `NO_PUBLICADO` en `dataset_unavailable` (3 intentos; `sql/consultas/2026-11-17_1435_players-sin-publicar-pendientes.sql`). 0 avisos ni errores en el log. Sigue sin verse el paso 9 lanzado por el propio comando de principio a fin | ✅ |

## 20. Aviso por Telegram de cada CSV procesado (plan `PLAN-telegram-csv-procesados.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | Vigilante `scripts\py\monitor\telegram_csv.py`: lee `public.batch_launch_request` cada 10 s y envía cada CSV terminado (`COMPLETED`/`FAILED`) como documento, con estado, batch, carpeta, hora y error; envío con `curl.exe` | Consulta real: 21 CSV terminados en 30 min; `getMe` del bot OK | ✅ |
| 2 | Servicio `telegram` en `asegurar.py` (el launcher depende de él) y comando `basket telegram [prueba\|una-vez\|chat]`; sin token o chat_id queda desactivado | `basket telegram chat` responde; compila | ✅ |
| 3 | Token solo en `config\basketball.local.env` (ignorado por git); claves vacías en `basketball.env` | `git check-ignore` lo confirma; test `test_token_no_esta_en_la_configuracion_versionada` | ✅ |
| 4 | Tests `TelegramCsvTests` (pie, límite 1024, configuración, marca de agua) | 5 tests OK; suite completa OK; gate `verificar.py` VERDE | ✅ |
| 5 | Prueba real en el móvil | `chat_id` obtenido con `basket telegram chat`; `basket telegram prueba` enviado; un CSV real (`PLAYER_STATS_20261117124906_8SJueQyq.csv`) enviado como documento; vigilante en marcha (`logs\telegram_csv.log`) | ✅ |
| 6 | Los datos del CSV van como texto (no el fichero): bloque `<pre>` con la cabecera repetida, mensajes de hasta 4096 caracteres, máximo `TELEGRAM_MAX_MENSAJES` (5) | 8 tests `TelegramCsvTests` OK; `PLAYER_STATS_20261117124906_8SJueQyq.csv` recibido como texto en 1 mensaje; vigilante reiniciado con el código nuevo | ✅ |
| 7 | Aviso de una línea por CSV: solo estado, nombre del CSV y hora de Madrid (sin fichero ni datos) | 50 tests OK; vigilante reiniciado 12:54:57; recibido `✅ COMPLETADO · POINT_BY_POINT_20261117125350_8ArlEYR6.csv · 17/11 12:54:49` | ✅ |
| 8 | `basket pronostico publicar` envía al bot solo la predicción (título, una línea por partido con hora de Madrid, ganador y probabilidad, y el enlace); un fallo de Telegram no impide publicar | Test `test_mensaje_pronostico_solo_prediccion_y_enlace` (51 tests OK); publicada la jornada 12 de Euroliga: `Artículo actualizado` y `Telegram: prediccion enviada al bot.` | ✅ |

## 21. SDD y gate al día con lo del 2026-11-17 (plan `PLAN-sdd-verificacion-17nov.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | `asegurar.py`: Grafana depende de Postgres, que arranca antes y deja aplicar las vistas `v_csv_procesados` y `v_csv_generados` (antes fallaban con "container is not running") | Con Postgres parado, `_ensure_service('grafana')` arrancó Postgres y dio `vista aplicada` en las dos (commit `af36a17`) | ✅ |
| 2 | `verificar.py` 6: vistas de Grafana presentes en Postgres | `OK Grafana: vistas v_csv_procesados y v_csv_generados en Postgres` | ✅ |
| 3 | `verificar.py` 7: Telegram configurado → un vigilante y ningún CSV terminado sin avisar más de 2 min; sin configurar se omite | `OK Telegram: un vigilante en marcha`, `OK Telegram: todos los CSV terminados avisados`; gate VERDE (17-nov) | ✅ |
| 4 | `SDD.md` §7 (resultados-ayer, pendientes hasta el projector, orden de arranque, skills autocontenidas), §9 (aviso por Telegram) y §13 (gate y tests) | Revisado a mano | ✅ |
| 5 | Skill `estado-del-sistema` borrada; sus menciones cambiadas por `basket estado` (commit `bdeda32`) | `grep estado-del-sistema` sin resultados salvo el comentario histórico de `estado.py` | ✅ |

## 22. `resultados-ayer` sin gastar tokens (plan `PLAN-resultados-ayer-sin-tokens.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | Al terminar, salga por donde salga, `resultados_ayer.py` imprime una línea `RESUMEN:` (ya estaban / n de m en Mongo / ligas o cargas con fallo / ERROR) y la manda al bot | `basket resultados-ayer` (17-nov, día 16): `RESUMEN: ✅ Resultados de ayer 16/11 · ya estaban los 8 en Mongo`, recibido en Telegram | ✅ |
| 2 | Tests `ResultadosAyerResumenTests` (ya estaban, todos, faltan + liga con fallo, error, sin partidos) | 56 tests OK | ✅ |
| 3 | Skill `resultados-ayer` fina: `model: haiku`, descripción 148 caracteres (antes 704), fichero 1.549 (antes 4.721), lee solo `RESUMEN:` | Revisada a mano | ✅ |
| 4 | La tarea programada "Basketball - Resultados de ayer al iniciar" ya existía (último resultado 0); ahora su resultado llega al bot | `schtasks /query` | ✅ |

## 23. Descripciones cortas de las skills (plan `PLAN-pendientes-sin-tokens.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | Descripción de 14 skills recortada a 124–148 caracteres (qué hace + cuándo usarla, sin mencionar otras skills); se cargan en cada mensaje | Total de descripciones cargadas: **6.230 → 2.177 caracteres** (−65 %, ~1.000 tokens menos por mensaje) | ✅ |
| 2 | `model: haiku` en `aviso-telegram` y `cuadrar-partidos-dia` | Frontmatter revisado | ✅ |

## 24. `pendientes` sin gastar tokens (plan `PLAN-pendientes-sin-tokens.md`)

| # | Cambio | Evidencia | Estado |
|---|---|---|---|
| 1 | `matchids_pendientes.py` termina con una línea `RESUMEN:` (procesados, errores, en Mongo y completos, quedan) que llega al bot; faltar secciones no es ❌ | `basket pendientes "" 1` (17-nov): `RESUMEN: ✅ Pendientes · 1 procesados · 1 de 1 en Mongo (0 completos) · quedan 54`, recibido en Telegram; camino de error probado: `❌ Pendientes · ERROR: el procesado termino con codigo 1 · quedan 55` | ✅ |
| 2 | `procesar_matchids.py`: un primer argumento vacío o solo comillas (`""`) cuenta como sin CSV de selección (antes fallaba con `No existe el CSV indicado: ""`) | La misma prueba procesó 1 partido | ✅ |
| 3 | Tests `PendientesResumenTests` y `TokensTests`; skill `procesar-pendientes` fina (lee solo `RESUMEN:`) | 61 tests OK | ✅ |
| 4 | `basket tokens` y `AHORRO-TOKENS.md` en la raíz (plan `PLAN-ahorro-tokens.md`) | Carga fija medida: 9.963 caracteres, ~2.490 tokens por mensaje | ✅ |

## Flujo diario sin tokens (`docs/PLAN-flujo-diario-sin-tokens.md`, 2026-11-17)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | `resultados-ayer` encadena `pendientes` al terminar (salvo `--solo-csv` o `RESULTADOS_AYER_PENDIENTES=0`); el código de salida es el peor de los dos | Tests `test_encadena_pendientes_salvo_solo_csv_o_variable` y `test_main_lanza_pendientes_y_devuelve_el_peor_codigo` | ✅ |
| 2 | La tarea activa «Resultados de ayer al iniciar» cubre el día; «Ciclo diario» sigue deshabilitada | `schtasks /query` el 17/11; documentado en `ESPECIFICACIONES.md` §7.2b | ✅ |
| 3 | `pendientes` avisa a Telegram «⏳ Pendientes: N partidos por procesar» al empezar; un fallo de Telegram no lo corta | Test `test_pendientes_avisa_a_telegram_al_empezar` | ✅ |
| 4 | Seguimiento sin Claude: dashboard de logs automático y `RESUMEN` a Telegram; skill `resultados-ayer` actualizada | Commit `fd1682d`; `SKILL.md` de `resultados-ayer` | ✅ |
| 5 | Gate | Tests 65 OK; `basket verificar` VERDE el 17/11 | ✅ |

## Jugadores con el mismo nombre abreviado (`docs/PLAN-jugadores-con-nombre-repetido.md`, 2026-11-17)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | `PLAYER_STATS` trae `player_url` emparejado por nombre y orden | `test_dos_jugadores_con_el_mismo_nombre_reciben_su_enlace`; `python-pyppeter` 347 tests OK | ✅ |
| 2 | `stats_player` usa `(match_id, team, player_key)`; acepta CSV de 24 o 25 columnas | `ResultRowTest` (5 OK); migración V2 aplicada; consulta `2026-11-17_1605_williams-j-okc-cargados.sql` | ✅ |
| 3 | El launcher guarda el motivo de un batch fallido | `BatchProcessExecutorMotivoTest` (4 OK); desplegado el 17/11 16:21, launcher UP | ✅ |
| 4 | Los 3 partidos de OKC tienen a los dos «Williams J.» | Postgres 27/22/26 jugadores con id; Mongo y `/api/v1/matches/h81tlrkd/players` igual | ✅ |
| 5 | Gate | Tests del repo 65 OK; `basket verificar` VERDE el 17/11 | ✅ |

## Aviso a Telegram por partido (`docs/PLAN-aviso-telegram-por-partido.md`, 2026-11-17)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | Tras cada partido, `✅/❌ i/N · partido · quedan N-i`; un fallo de Telegram no corta | `test_pendientes_avisa_de_cada_partido_y_cuantos_quedan` | ✅ |
| 2 | Gate | Tests 66 OK; `basket verificar` VERDE el 17/11 | ✅ |

## CSV que faltan por generar (`docs/PLAN-csv-que-faltan.md`, 2026-11-18)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | `basket csv-faltan [match_id]` cruza auditoría, CSV en disco y último intento | `test_csv_faltan_cruza_disco_e_intentos`; ejecución real: Gr62XNa6 → `ERROR: …ERR_NAME_NOT_RESOLVED`, 4 partidos euroleague del 17/11 sin CSV | ✅ |
| 2 | El motivo del error es la línea de la excepción, no el volcado de la pila | `test_motivo_error_salta_el_volcado_de_la_pila` | ✅ |
| 3 | Gate | Tests 71 OK y `basket verificar` VERDE en main el 18/11 tras fusionar | ✅ |

## «Extrayendo ahora» en el dashboard de pendientes (`docs/PLAN-grafana-extrayendo.md`, 2026-11-18)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | `reextraer` (y `resultados-ayer`) apuntan cada partido y dataset en `pipeline_step` | `test_seguimiento_genera_sql_seguro_y_no_corta_si_falla`; fila real id 374 creada y cerrada (`2026-11-18_0945_prueba-seguimiento-pipeline-step.sql`) | ✅ |
| 2 | Dashboard `fixtures-audit-live` con paneles «Extrayendo ahora» y «Ultimos pasos (2 h)» | Publicado en Grafana (versión 7); `csv-extra-batch` en el commit del submódulo | ✅ |
| 3 | Visto en vivo | Pendiente de la próxima ejecución con esta rama fusionada | ⏳ |

## Fecha y hora de los partidos en la web (`docs/PLAN-fechas-partidos-utc.md`, 2026-11-19)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | Análisis de los 40 últimos partidos | 40/40 con la hora UTC (una hora menos); 2/40 (`QgwzkCi3`, `0GolR8ad`) con el día anterior; 67 en todo `results` (`2026-11-19_1010_dia-partidos-desfasado.sql`) | ✅ |
| 2 | El projector guarda `eventDatetime` en ISO-8601 UTC (`…Z`) | `EventDatetimeInstantTest` (3 tests); projector 7 tests OK; commit `726f5db` | ✅ |
| 3 | Reproyección de lo existente (`PROJECTION_VERSION` v3) | Mongo: 3533/3533 `matches` con `Z`, 0 con el formato antiguo en `matches` y `player_performances` | ✅ |
| 4 | La web muestra la hora de Madrid | Navegador (Europe/Madrid): 40/40 coinciden con `event_time`; Besiktas–Real Madrid `18 nov, 18:00`; Celtics–Mavericks `16 nov, 00:00` | ✅ |
| 5 | Gate | `basket verificar` VERDE el 19/11 | ✅ |

## Grandes remontadas (`docs/PLAN-remontadas.md`, 2026-11-20)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | Consulta SQL de partidos ganados tras ≥ 15 puntos en contra | `2026-11-20_1000_partidos-ganados-tras-gran-remontada.sql`: 59 de 888 partidos con jugadas; mayor, 76ers–Cavaliers (`vqjr83tS`), 29 | ✅ |
| 2 | `GET /api/v1/comebacks` (`minDeficit`, `competition`, `limit`) | `ComebackCalculatorTest` (6) y `ComebackServiceTest` (4); `mvnw verify` 45 tests y JaCoCo ≥ 80 % (con `PredictionArticleServiceImplTest`, el umbral ya fallaba en 0,79); API `8a0d31e` | ✅ |
| 3 | La API coincide con la consulta SQL | `diff` de `matchId`, puntos y prórroga: 59/59 iguales; respuesta en ~1,5 s | ✅ |
| 4 | Pantalla `/comebacks` con filtros y enlace «Remontadas» | `comebacks.test.ts` (5); `typecheck` y 36 tests OK; web `0a6cb42`. Navegador: 59 partidos; filtro euroleague → 4 (Valencia 18); vista móvil en fichas | ✅ |
| 5 | Gate | `basket verificar` VERDE el 20/11 | ✅ |
| 6 | Ordenar por remontada (mayor/menor) o por fecha, sin recargar | `sortComebacks` (3 tests; web 39 tests y `typecheck` OK). Navegador: «Menor remontada» empieza por las de 15 y «Más reciente» por Lakers–Hornets del 18/11; el contador de llamadas a `/api/v1/comebacks` sigue en 1 | ✅ |

## Curiosidades (`docs/PLAN-curiosidades.md`, 2026-11-20)

| # | Requisito | Evidencia | Estado |
|---|---|---|---|
| 1 | Consultas SQL de curiosidades | `2026-11-20_2230_partidos-con-mas-puntos-por-cuarto.sql`, `_2300_curiosidades-jugada-a-jugada.sql`, `_2330_curiosidades-resultados.sql`, `_2345_curiosidades-jugadores.sql`; control de calidad: 2643 jugadas de 882 partidos con `*_points_added` mal en la 1ª jugada del cuarto (lo arregla otra sesión) | ✅ |
| 2 | `GET /api/v1/curiosities` (`competition` opcional, caché 5 min) | `CuriosityCalculatorTest` (13) y `CuriosityServiceTest` (4); `mvnw verify` 62 tests y JaCoCo OK; API `claude/curiosidades` | ✅ |
| 3 | La API coincide con las consultas | Script de comparación: 16/16 secciones iguales fila a fila (sin filtro); respuesta ~2 s sin caché | ✅ |
| 4 | Pantalla `/curiosities` con pestañas, filtro y enlace en la cabecera | `curiosities.test.ts` (4); web 43 tests y `typecheck` OK. Navegador: 893 partidos; cambiar de pestaña no llama a la API; liga-endesa → 72; móvil sin desbordar | ✅ |
| 5 | Gate | `basket verificar` VERDE el 20/11 | ✅ |
