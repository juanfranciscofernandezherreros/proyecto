---
name: procesar-csv-resultados
description: Lee los CSV de resultados (RESULTS) que ya están en disco y los carga en PostgreSQL para todas las ligas o para una, sin volver a extraer nada de Flashscore. Usar cuando el usuario pida procesar, importar, cargar o reprocesar los CSV de resultados, o cuando los CSV existan pero los datos no estén en la base de datos. Si lo que quiere es traer resultados nuevos de la web, usar resultados-todas-las-ligas o extraer-resultados.
model: haiku
---

# Procesar los CSV de resultados

Carga en `results.results` los ficheros `RESULTS_<fecha>_<pais>_<competicion>.csv`
de `C:\data\basketball\competitions\<pais>\<competicion>\`. **No abre el navegador
ni toca Flashscore**: solo trabaja con lo que ya está en disco. Son tres llamadas,
sin pedir permiso entre una y otra.

## 1. Estado antes

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd estado"
```

Guardar de `RESULTADOS POR LIGA` el número de partidos de cada liga. Si Postgres o
Docker no responden, parar y decirlo.

## 2. Procesar

En segundo plano (unos 30 segundos por liga), con ruta completa y la salida a un
fichero del directorio temporal de la sesión:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd procesar-csv"
```

| Llamada | Qué procesa |
|---|---|
| `PROCESAR_CSV_RESULTADOS.bat` | El CSV más reciente de cada una de las 11 ligas |
| `PROCESAR_CSV_RESULTADOS.bat EUROLIGA` | El más reciente de esa liga (`code` de `LIGAS_BASKET.json`) |
| `PROCESAR_CSV_RESULTADOS.bat ALL todos` | Todos los CSV de cada liga, del más antiguo al más reciente |

- Por defecto basta el más reciente: cada RESULTS es la página completa de
  resultados, así que contiene a los anteriores. Usar `todos` solo si el usuario
  pide expresamente reprocesar el histórico; son unos 100 ficheros y tarda cerca
  de una hora.
- Asegura Postgres y el launcher, envía cada CSV al launcher y comprueba en
  Postgres que están todos los partidos del fichero.
- La carga es idempotente: repetirla no duplica partidos.
- Un fallo en una liga no detiene las demás.
- Al terminar, leer **solo** el bloque `RESUMEN` (`grep -A 20 "RESUMEN"`): una
  fila por CSV con sus filas y su estado (`OK`, `FALLO`, `OMITIDO`). No volcar el
  log entero.

## 3. Estado después

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd estado"
```

## Qué contar al usuario

Una tabla corta, liga a liga: fichero procesado, filas del CSV, estado y partidos
nuevos en la base de datos (diferencia entre el paso 1 y el 3). Si no ha entrado
ninguno, decirlo tal cual: los CSV ya estaban cargados.

## Si algo falla

- **`OMITIDO`, sin CSV**: esa liga no tiene ningún RESULTS en disco. Hay que
  extraerlo (skill `extraer-resultados`).
- **"partidos sin marcador o sin los cuatro parciales"**: el importador rechaza el
  CSV entero si alguna fila viene incompleta. Decir qué liga es; se arregla
  volviendo a extraerla, no editando el CSV a mano.
- **"no es un RESULTS de ... dentro de la ruta canónica"**: el fichero está en una
  carpeta con un nombre de competición no canónico (`spain\acb`, `israel\super-league`).
- **El launcher no responde**: `ESTADO.bat` lo muestra con `0`; el propio `.bat`
  intenta arrancarlo.

## Avisos

- Solo procesa RESULTS. Para los CSV de jugada a jugada y estadísticas, skill
  `procesar-pendientes`.
- No copiar CSV a mano a `C:\data\basketball-ready\current`.
- La web tarda ~1 min en reflejar los datos y solo si está levantada (skill
  `arrancar-web`).
- No se hace commit ni push salvo que el usuario lo pida.
