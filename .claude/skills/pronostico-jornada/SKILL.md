---
name: pronostico-jornada
description: Hace el pronóstico de la próxima jornada de una liga (por defecto la Euroliga) con los resultados de PostgreSQL, redacta el artículo de previa y lo publica en la sección Pronósticos de la web del proyecto Basketball. Usar cuando el usuario pida un pronóstico, una previa, una predicción o un artículo de la próxima jornada, quién va a ganar los próximos partidos, o actualizar la previa ya publicada. No extrae resultados (para eso, resultados-todas-las-ligas) ni usa cuotas o lesiones.
---

# Pronóstico y previa de la próxima jornada

Tres pasos: el script calcula los números, tú redactas, el script publica. Los números
no se tocan a mano.

## 1. Comprobar que los resultados están al día

El pronóstico solo vale lo que valgan los resultados cargados. Mirar la liga en:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd comprobar"
```

Si la liga tiene partidos jugados sin resultado, decirlo y ofrecer la skill
`extraer-resultados` antes de seguir. No extraer por iniciativa propia.

## 2. Calcular el pronóstico

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd pronostico datos"
```

- Sin argumentos es la Euroliga. Otra liga: `pronostico datos <pais> <competicion>` con
  los slugs de `fixtures.fixtures` (por ejemplo `spain liga-endesa`).
- Corta la jornada en cuanto un equipo se repite, calcula el margen esperado y la
  probabilidad de cada partido e imprime la lista con el ganador previsto.
- Deja el borrador en `C:\data\basketball\reports\pronosticos\<id>.json` (la ruta
  exacta sale en la última línea). Trae los textos vacíos.
- Si falla con "Equipos de la jornada sin partidos jugados", el nombre de ese equipo no
  coincide entre el calendario y los resultados: contarlo y parar, no inventar datos.

Criterio (el de `csv-extra-batch\pronostico\README.md`): 65 % diferencial de puntos de
la temporada, 35 % el de los últimos cinco partidos, 2,5 puntos de localía, logística
de escala 9. La consulta que usa es
`sql\consultas\2026-11-15_2330_previa-jornada-datos.sql` (ya guardada).

## 3. Redactar

Leer el borrador entero y rellenar con Edit, sin tocar ningún otro campo:

- `introduction`: 3 o 4 párrafos separados por una línea en blanco. Contexto de la
  jornada (fechas, cuántos partidos), qué equipos llegan mejor y peor, cuántos
  favoritos claros hay y cuál es el partido más abierto, y un último párrafo con los
  límites (solo resultados de la base de datos, sin lesiones ni cuotas).
- `analysis` de cada partido: 2 o 3 frases con los datos que explican el pronóstico y,
  si lo hay, el dato que lo matiza (balance en casa o fuera, forma reciente).

Los datos para escribir están en el propio borrador: `_ayuda.clasificacion` (todos los
equipos: balance, puntos a favor y en contra, diferenciales, victorias en los últimos
cinco, balance en casa y fuera) y `games[]._ayuda` (los dos equipos del partido y el
margen del local). Las claves `_ayuda` no se publican.

Normas de redacción:

- Cada cifra y cada comparación del texto ("el mejor visitante", "el que más encaja",
  "cuatro de cinco") se contrasta con `_ayuda.clasificacion` antes de publicar. Repasar
  también los recuentos de la introducción (cuántos favoritos superan el 70 %, cuántos
  son visitantes) contando sobre la lista de partidos.
- No añadir nada que no esté en los datos: ni jugadores, ni lesiones, ni fichajes, ni
  rachas históricas. El conocimiento propio sobre plantillas puede estar desfasado.
- No cambiar `prediction`, `winner`, `winnerProbability` ni `methodology`.
- Español, frases cortas, sin exagerar la certeza: una probabilidad del 57 % es un
  partido abierto.

## 4. Publicar y comprobar

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd pronostico publicar <ruta-del-borrador>"
```

- Si falta la introducción o algún análisis, lo lista y no publica.
- Guarda el artículo en `prediction_articles` de MongoDB. Si ya hay una previa de esa
  competición, jornada y fecha de inicio, la actualiza (dice "Artículo actualizado");
  si no, la crea. Imprime la dirección del artículo.
- Comprobar que se ve: abrir esa dirección (`http://localhost:8083/predictions/<id>`).
  Si la web no responde, skill `arrancar-web`.

## Qué contar al usuario

La tabla de partidos ordenada de mayor a menor probabilidad (ganador previsto,
probabilidad, margen, confianza), el pronóstico más claro, el más abierto, el enlace
al artículo y los límites: sale solo de los resultados cargados, sin lesiones ni
cuotas, y las probabilidades no están calibradas.
