---
name: resultados-todas-las-ligas
description: Extrae solo los resultados (marcadores y parciales) de todas las ligas de baloncesto a la vez y los carga en PostgreSQL, sin jugada a jugada ni estadísticas. Usar cuando el usuario pida los resultados de todas las ligas, actualizar todas las ligas, o ponerse al día de marcadores en general. Para una sola liga, usar extraer-resultados.
model: haiku
---

# Resultados de todas las ligas

Solo marcadores y parciales de las 11 ligas de `LIGAS_BASKET.json`. No lanza jugada
a jugada, estadísticas ni pendientes. Son tres llamadas, sin pedir permiso entre
una y otra.

## 1. Estado antes

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd estado"
```

De la sección `RESULTADOS POR LIGA`, guardar por cada liga el número de partidos y
los jugados sin resultado, para comparar al final. Si Postgres o Docker no
responden, parar y decirlo.

## 2. Extraer e importar

En segundo plano (unos 15 minutos), con ruta completa y la salida a un fichero del
directorio temporal de la sesión:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd resultados ALL"
```

- Para cada liga baja la página de resultados de Flashscore, genera el CSV y lo
  importa en `results.results`. No hace falta ningún paso más.
- Un fallo en una liga no detiene las demás.
- Al terminar, leer **solo** el bloque `RESUMEN` del final del fichero
  (`grep -A 30 "RESUMEN"`): una fila `RESULTS extraer` y otra `RESULTS importar`
  por liga. No volcar el log entero.
- El mismo resumen queda en
  `C:\data\basketball\reports\orchestrator\ligas-orquestar-resumen-<fecha>.csv`.

## 3. Estado después

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd estado"
```

## Qué contar al usuario

Una tabla corta, liga a liga:

- cuántos partidos nuevos han entrado (diferencia de partidos entre el paso 1 y el 3);
- qué ligas siguen con partidos jugados sin resultado;
- qué ligas fallaron, con el detalle del resumen, ofreciendo repetirlas solas con
  la skill `extraer-resultados`.

Si no ha entrado ningún partido en ninguna liga, decirlo tal cual: puede que no se
haya jugado nada desde la última extracción.

## Avisos

- Si `config\basketball.env` tiene `FILTRO_PAIS` o `FILTRO_COMPETICION`, `ALL`
  procesa solo esas ligas. Si en el resumen faltan ligas, avisar.
- No usar `mvn spring-boot:run` ni lanzar piezas sueltas del scraper.
- La web tarda ~1 min en reflejar los datos y solo si está levantada (skill
  `arrancar-web`).
- No se hace commit ni push salvo que el usuario lo pida.
