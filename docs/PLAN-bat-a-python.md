# PLAN — Convertir todos los `.bat` y `.ps1` a Python

**Objetivo:** sustituir los 42 `.bat` (20 en `1_EJECUTAR\`, 22 en `scripts\`) y los
26 `.ps1` de `scripts\` por Python puro, **sin PowerShell**, sin cambiar el flujo de
datos ni los puertos, de forma que el usuario pueda ejecutar cada pieza directamente
(token cero) y que los contratos del SDD se mantengan intactos.

> Regla del proyecto (`flujo-bug-plan-sdd-commit-por-paso`): este plan va primero;
> cada paso se implementa, se verifica con `Verificar.ps1`/`VERIFICAR.bat` (hasta que
> exista su equivalente Python) y se cierra con **commit + push** en el repo padre.
> La evidencia de cada paso se anota en `docs\VERIFICACION-SDD.md`.

## Principios de la conversión

1. **No romper el flujo del SDD §4**: CSV → launcher (`:8088`) → Postgres (`:55432`)
   → projector → Mongo (`:27017`) → API (`:8082`) → web (`:8083`). Puertos intactos.
   Nunca `mvn spring-boot:run` ni `npm run dev`.
2. **Paridad antes que elegancia**: cada módulo Python replica la salida y el código
   de salida (0/1) del `.bat`/`.ps1` que sustituye. Se verifica comparando la salida
   del original con la del nuevo sobre los mismos datos antes de borrar el original.
3. **Un paquete Python** en `scripts\py\` (ya existe, con `estado_lib.py` y los tres
   orquestadores). Estructura espejo de `scripts\`:
   ```
   scripts\py\
     __init__.py
     config.py            # <- config.ps1 (fundacional, todo depende de el)
     estado.py            # ya hecho
     estado_lib.py        # ya hecho (se refactoriza sobre config.py)
     verificar.py         # <- Verificar.ps1
     proc.py              # helper comun: ejecutar proceso, capturar, codigo salida
     arranque\  extraer\  importar\  ligas\  pendientes\  monitor\
     lanzadores\          # <- los 20 de 1_EJECUTAR
   ```
4. **Doble clic / Task Scheduler**: donde haga falta lanzar con doble clic o desde el
   Programador de tareas de Windows, se deja un **shim `.cmd` de una línea**
   (`@python "%~dp0..\scripts\py\lanzadores\X.py" %*`). No es PowerShell ni lógica:
   es solo el punto de entrada de Windows. Las `TAREA_*` registradas en el Programador
   se vuelven a registrar apuntando al nuevo shim (paso 8).
5. **Dependencias**: Python 3.14 del sistema. Nuevo `scripts\py\requirements.txt`
   (p. ej. `requests` para HTTP al launcher/auditoría; `psycopg[binary]` solo si algún
   `.ps1` habla directo con Postgres —a confirmar al leer cada uno—; docker vía
   `subprocess` a `docker compose`, sin SDK). Reutilizar el intérprete del scraper
   (`python-pyppeter\.venv`) cuando se invoque `flashscore.py`.
6. **Reglas vigentes**: idioma español en código y mensajes (`idioma-espanol`); toda
   consulta SQL que se ejecute se guarda en `sql\consultas\` (`consultas-sql.md`).

## Capas y orden (de abajo arriba)

El orden es por dependencias: nada se convierte antes que aquello de lo que depende.

### Paso 0 — Fundación: configuración y helpers
- `config.ps1` → **`config.py`**: lee `config\basketball.env` + `basketball.local.env`,
  prioridad env > local > default, resuelve `${CLAVE}`, localiza JDK 21. API:
  `cargar()` -> dict; `ruta(clave)`. Mantener `config.ps1` temporalmente para
  `config.bat` hasta el paso 7.
- **`proc.py`**: helper para lanzar procesos (reemplaza el patrón `%PS% -File ...`),
  capturar salida con eco opcional y propagar el código de salida.
- Refactor de `estado_lib.py` para usar `config.py` en vez de invocar `config.ps1`.
- **Verificación**: `python -c "import config,proc"`; `config.py` imprime las mismas
  claves que `config.ps1 -FormatoBat` (diff vacío).

### Paso 1 — Estado y verificación (solo lectura)
- `Estado.ps1` → **`estado_sys.py`** (la lógica de ESTADO; `estado.py` ya resume).
- `Verificar.ps1` → **`verificar.py`** (gate del SDD §13).
- `validar_limite.bat` → función en `proc.py`/`config.py`.
- **Verificación**: salida de `estado_sys.py` == `ESTADO.bat`; `verificar.py` da el
  mismo veredicto y código que `VERIFICAR.bat`.

### Paso 2 — Arranque (docker + servicios + antibloqueo)
- `arranque\ASEGURAR_SERVICIOS.ps1` + `ASEGURAR.bat` → **`arranque\asegurar.py`**
  (docker compose up de lo pedido; espera a que respondan).
- `MANTENER_DESPIERTO.ps1`/`.bat`, `INICIAR_ANTIBLOQUEO.bat`,
  `INICIAR_WATCHER_CSV.bat`, `ACTUALIZAR_EDGEDRIVER.ps1` → módulos en `arranque\`.
- **Verificación**: con el stack parado, `asegurar.py` lo levanta y `estado_sys.py`
  da código 0.

### Paso 3 — Importadores a Postgres
- `importar\IMPORTAR_RESULTADOS_TODAS.ps1`, `IMPORTAR_RESULTADOS_EUROLIGA_A_POSTGRESQL.ps1`,
  `PROCESAR_{PLAYER,TEAM}_STATS_*`, `PROCESAR_POINT_BY_POINT_*` → `importar\*.py`.
- `IMPORTAR_*.bat` → shims/entradas.
- **Verificación**: reimportar un CSV ya cargado es idempotente (0 nuevos) y el
  resumen OK/FALLO/OMITIDO coincide con el `.ps1`. Si alguna consulta SQL se ejecuta,
  guardarla en `sql\consultas\` (`consultas-sql.md`).

### Paso 4 — Extractores (scraper Flashscore)
- `extraer\EXTRAER_DATASET_PENDIENTE.ps1`, `EXTRAER_PLAY_BY_PLAY_PENDIENTE.ps1`,
  `PARTIDOS_YA_IMPORTADOS.ps1` + `EXTRAER_*.bat` → `extraer\*.py`
  (invocan `flashscore.py` con el intérprete del scraper).
- **Verificación**: extraer una liga con límite pequeño genera el mismo CSV que el
  `.ps1` (mismas columnas/filas).

### Paso 5 — Orquestadores de ligas
- `ligas\ORQUESTAR_LIGAS.ps1`, `EJECUTAR_LIGA_BASKET.ps1`,
  `EJECUTAR_TODAS_LAS_LIGAS.ps1`, `PROCESAR_ULTIMOS_PARTIDOS_COMPLETO.ps1` →
  `ligas\*.py`. Reutilizan paso 3 y 4.
- **Verificación**: `orquestar.py EUROLIGA results 5` produce el mismo CSV de resumen
  `ligas-orquestar-resumen-*.csv` que `LIGAS_ORQUESTAR.bat`.

### Paso 6 — Pendientes, auditoría y monitor
- `pendientes\PROCESAR_MATCHIDS_PENDIENTES.ps1`, `ARCHIVAR_CSV_REPETIDOS.ps1`,
  `FIXTURES_SIN_RESULTS.bat` → `pendientes\*.py`.
- `monitor\RECOLECTAR_CONSUMO.ps1`, `VER_PENDIENTES_FIXTURES_EN_VIVO.ps1`,
  `watch_csv_processing.ps1` + `.bat` → `monitor\*.py`.
- **Verificación**: la auditoría devuelve `fixtures/elegibles/pendientes` iguales a
  `AUDITORIA_FIXTURES.bat` sobre el mismo estado.

### Paso 7 — Lanzadores de `1_EJECUTAR\` (los 20)
Cada `.bat` pasa a `scripts\py\lanzadores\<nombre>.py` + shim `.cmd` del mismo nombre
en `1_EJECUTAR\` (para doble clic). Agrupados:
- Ya cubiertos por `scripts\py\` existentes: `ESTADO`, `EXTRAER_RESULTADOS`(ALL),
  `PROCESAR_CSV_RESULTADOS` → unificar con los módulos nuevos.
- Resto: `ARRANCAR_TODO`, `ANTIBLOQUEO`, `AUDITORIA_FIXTURES`, `AUTOMATICO_INICIO`,
  `CICLO_DIARIO`, `COMPROBAR_RESULTS_FIXTURES`, `DATOS_EUROLIGA`, `EXTRAER_CSV_COMPLETO`,
  `GRAFANA_PENDIENTES`, `IDS_PARTIDOS_AYER`, `LIGAS_ORQUESTAR`, `LIGAS_RESULTADOS`,
  `MATCHIDS_PENDIENTES`, `MONITOR_PENDIENTES`, `ULTIMOS_PARTIDOS`, `VERIFICAR`,
  `VIGILAR_SERVICIOS`.
- Retirar `config.bat` cuando ya nada lo use.
- **Verificación**: cada lanzador nuevo da la misma salida y código que su `.bat`.

### Paso 8 — Programador de tareas y limpieza
- Reapuntar las tareas de Windows (`TAREA_DIARIA`, `TAREA_INICIO`, `TAREA_VIGILANCIA`)
  a los shims nuevos; conservar `CICLO_DIARIO`/`AUTOMATICO_INICIO`.
- Actualizar referencias en skills (`.claude\skills\*`), `CLAUDE.md`, `README.md` y
  `AUTOMATICO_INICIO`/`CICLO_DIARIO` para que citen los `.py`.
- Borrar los `.bat`/`.ps1` ya reemplazados (dejando solo shims `.cmd` donde Windows
  los necesite).
- **Verificación**: `VERIFICAR` (ya en Python) en verde; `estado` código 0; una
  pasada de `CICLO_DIARIO` en Python sin errores.

## Commits

Un commit + push por paso (0–8), en el repo padre `proyecto` (los `.bat`/`.ps1`/`.py`
están todos en la raíz, no en submódulos). Mensaje en español. Evidencia en
`docs\VERIFICACION-SDD.md` por paso.

## Riesgos

- Los `.ps1` de importación pueden hablar con Postgres o con el launcher de formas no
  obvias: **leer cada uno antes de convertirlo** (no asumir). Confirmar deps en el paso
  donde se usan.
- Task Scheduler guarda rutas absolutas a `.bat`: hay que re-registrar, no basta con
  renombrar (paso 8).
- La paridad de salida es el criterio de aceptación: ante cualquier diferencia, gana el
  comportamiento del `.ps1` original.

## Estado

- [x] Paso previo (sesión anterior): `estado.py`, `resultados_todas.py`,
  `procesar_csv_resultados.py`, `estado_lib.py` en `scripts\py\`.
- [ ] Pasos 0–8 pendientes.
