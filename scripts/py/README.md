# Pipeline en Python (`scripts\py\`)

Todo el pipeline del proyecto corre en **Python puro, sin PowerShell**. El punto de
entrada único es el CLI **`basket`**.

## Uso rápido

```bash
basket                      # menú interactivo (o doble clic en 1_EJECUTAR\basket.cmd)
basket ayuda               # lista de comandos
basket estado              # estado del sistema
basket resultados EUROLIGA # extraer RESULTS de una liga
basket ciclo-diario        # ciclo diario completo
```

`basket.cmd` (en `1_EJECUTAR\`) es solo el punto de entrada de Windows; llama a
`scripts\py\basket.py`, que despacha a los lanzadores de `scripts\py\lanzadores\`.

## Estructura

| Carpeta | Qué |
|---|---|
| `config.py` | Configuración única (lee `config\basketball.env`). Fundacional. |
| `basket.py` | CLI con subcomandos coherentes. |
| `lanzadores\` | Un módulo por comando (`estado`, `arrancar_todo`, `ciclo_diario`…). |
| `arranque\` | Docker/servicios (`asegurar.py`), antibloqueo, driver de Edge, tareas del Programador. |
| `extraer\` | Scraper de Flashscore (resultados y datasets por partido). |
| `importar\` | Carga en Postgres vía launcher. |
| `ligas\` | Orquestación por liga (`orquestar.py`, `ejecutar_liga.py`…). |
| `pendientes\` | Procesar pendientes, archivar, comprobaciones. |
| `monitor\` | Monitores en vivo y recolector de consumo. |

Dependencias: Python 3 + `psutil` (ver `requirements.txt`); el resto es librería estándar.

## Programador de tareas

`python scripts\py\arranque\tareas.py <diaria|inicio|vigilancia> <instalar|quitar|estado|ejecutar> [valor]`
registra las tareas de Windows apuntando a `basket.cmd <comando>`.

## Scripts de resumen (opcionales)

`estado.py`, `resultados_todas.py` y `procesar_csv_resultados.py` (en esta carpeta)
son envoltorios que hacen **estado antes → carga → estado después** con una tabla
liga a liga. Equivalen a `basket estado` / `basket resultados` / `basket procesar-csv`
pero añadiendo la comparación antes/después.
