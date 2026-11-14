# Orquestadores en Python (sin gastar tokens)

Versión en Python de tres skills que eran secuencias fijas sin decisiones. Las
ejecutas tú directamente (token cero); la skill del mismo nombre queda como
*fallback* para cuando el script falle o quieras que Claude interprete la salida.

Cada script hace: **ESTADO antes → la carga → ESTADO después** y te imprime una
tabla liga a liga con los partidos nuevos y lo que sigue fallando.

| Script | Equivale a la skill | Qué hace |
|---|---|---|
| `estado.py` | `estado-del-sistema` | Resumen del estado, ordenado por lo que falla y con el script que lo arregla. Solo lectura. |
| `resultados_todas.py` | `resultados-todas-las-ligas` | Extrae RESULTS de las 11 ligas (`EXTRAER_RESULTADOS.bat ALL`, ~15 min) y compara antes/después. |
| `procesar_csv_resultados.py` | `procesar-csv-resultados` | Carga en Postgres los CSV de RESULTS ya en disco (`PROCESAR_CSV_RESULTADOS.bat`). No toca Flashscore. |

## Uso

```bash
python scripts\py\estado.py
python scripts\py\resultados_todas.py
python scripts\py\procesar_csv_resultados.py            # más reciente de cada liga
python scripts\py\procesar_csv_resultados.py EUROLIGA   # solo una liga
python scripts\py\procesar_csv_resultados.py ALL todos  # histórico completo
```

Código de salida: 0 = bien, 1 = falta algo (el mismo de los `.bat`).

`estado_lib.py` es la librería compartida: ejecuta `ESTADO.bat`, parsea su salida
y lee la configuración vía `scripts\config.ps1`. No se ejecuta directamente.

No sustituyen a las skills que sí necesitan criterio (`arrancar-web`,
`procesar-pendientes`, `commit-multirepo`, diagnósticos): esas siguen igual.
