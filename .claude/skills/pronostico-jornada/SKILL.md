---
name: pronostico-jornada
description: Pronóstico y artículo de previa de la próxima jornada de una liga, publicado en la web y en el bot. Usar cuando pidan una previa o predicción.
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
de escala 14 (antes 9; calibrada el 2026-11-21). La consulta que usa es
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
- **Buscar información en internet** (WebSearch y, para leer una página, el agente `web-fetch`) y
  añadirla a cada `analysis` como un párrafo final «Bajas y noticias»: informes de lesiones de la
  Euroliga (Eurohoops publica uno por jornada; el de la jornada que se pronostica sale el mismo día
  del partido, así que hay que citar el último disponible con su fecha), fichajes y crónicas del
  último partido. Reglas: solo lo que diga la página leída (nada de memoria propia sobre plantillas),
  con el nombre del jugador, el motivo y desde cuándo si lo dice; ignorar páginas de otras
  temporadas (la búsqueda mezcla la 2025-26); decir «sin motivo indicado» cuando la fuente no lo da;
  cuidar los nombres (en las fuentes Lyon-Villeurbanne es ASVEL). Poner las URLs en `sourceUrls` de
  cada partido y en `sources` del artículo (`{title, url}`), y una frase en la introducción que diga
  que esas notas no entran en las probabilidades.
- Sin búsqueda o si falla, decirlo en la introducción; no rellenar con suposiciones.
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
- Envía al bot de Telegram solo la predicción: el título, una línea por partido
  (`17/11 17:00  Dubai - Anadolu Efes → Dubai 63%`) y el enlace. Ni introducción ni
  análisis. Imprime `Telegram: prediccion enviada al bot.`; si Telegram falla o no
  está configurado, solo avisa y la publicación queda hecha.
- Comprobar que se ve: abrir esa dirección (`http://localhost:8083/predictions/<id>`).
  Si la web no responde, skill `arrancar-web`.

## Qué contar al usuario

La tabla de partidos ordenada de mayor a menor probabilidad (ganador previsto,
probabilidad, margen, confianza), el pronóstico más claro, el más abierto, el enlace
al artículo y los límites: sale solo de los resultados cargados, sin lesiones ni
cuotas, y las probabilidades no están calibradas.
