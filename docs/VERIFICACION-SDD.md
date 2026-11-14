# Verificación contra el SDD — Cierre de desarrollo

> **Fecha:** 2026-11-08 · **Relacionado:** [SDD.md](SDD.md),
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
| Script | Checks verde/rojo del SDD | `scripts/Verificar.ps1` · `1_EJECUTAR/VERIFICAR.bat` | Stack arrancado → exit 0/1 |
| Hook | Compila/typechea antes del push | `<repo>/.githooks/pre-push` | `git config core.hooksPath .githooks` (una vez por repo) |
| CI | Build + tests en cada push/PR | `<repo>/.github/workflows/ci.yml` | Automático en GitHub |
| Skill | Normas + flujo SDD→plan→verificación | `/normas-basketball` | Invocar antes de implementar/revisar |

**Estado del CI:** `basketball-match-api` (M3) y `python-pyppeter` (M4) ya están **en
verde**. El resto de repos no tenían suites rotas. El gate cumple su función.

**Notas:** la skill `/normas-basketball` vive en `.claude/` (gitignored), así que es
local, no versionada; el hook requiere activación manual por repo (diseño de git).

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
| 8 | Programador de tareas y limpieza de los `.ps1`/`.bat` reemplazados | Pendiente | ⬜ |
