# Plan: skill `pronostico-jornada`

Petición del 2026-11-15: convertir en skill lo que se hizo a mano para la jornada 12 de
Euroliga: sacar la próxima jornada, calcular el pronóstico de cada partido, redactar el
artículo y publicarlo en la sección Pronósticos de la web.

## Alcance

- Un comando nuevo del CLI, `basket pronostico`, con dos pasos:
  - `datos [pais] [competicion]`: lee Postgres (consulta guardada), corta la próxima
    jornada, calcula margen y probabilidad y deja un borrador JSON sin textos.
  - `publicar <fichero>`: valida que el borrador tiene introducción y análisis y lo guarda
    en `prediction_articles` de MongoDB (actualiza el artículo de esa jornada si ya existe).
- La skill encadena los dos pasos y deja a Claude la redacción (introducción y análisis de
  cada partido), con la norma de contrastar cada cifra del texto contra los datos.
- Criterio numérico: el de `csv-extra-batch\pronostico\README.md` (65 % diferencial de
  temporada, 35 % últimos cinco partidos, 2,5 puntos de localía, logística de escala 9).
- Fuera de alcance: lesiones, cuotas y fuentes externas; el módulo Java `pronostico` y su
  redacción con Ollama no se tocan.

## Encaje con el SDD

- §4: no cambia el flujo de datos; lee Postgres y escribe solo en la colección
  `prediction_articles`, la misma que ya usa el módulo `pronostico`.
- §6.1: la API y la web no cambian; el documento respeta el contrato de `PredictionArticle`.
- §3.2: sin puertos ni servicios nuevos.

## Backlog

- [x] Revisar cómo consultan Postgres los scripts y cómo se registra un comando en `basket.py`.
- [x] Escribir este plan.
- [x] Guardar la consulta `sql\consultas\2026-11-15_2330_previa-jornada-datos.sql` (salida JSON).
- [x] `scripts\py\pronostico\previa.py`: corte de jornada, margen, probabilidad, borrador, validación y publicación.
- [x] `scripts\py\lanzadores\pronostico.py` y alta de `pronostico` en `scripts\py\basket.py`.
- [x] Tests de la lógica pura en `tests\test_scripts_py.py`; `python -m unittest discover -s tests` en verde.
- [x] `.claude\skills\pronostico-jornada\SKILL.md` y fila en `CLAUDE.md`.
- [x] Prueba completa: `basket pronostico datos` reproduce las probabilidades de la jornada 12 y `publicar` actualiza el artículo existente sin duplicarlo; comprobado en la web.
- [x] Evidencia en `docs\VERIFICACION-SDD.md`.
- [ ] Commit + push (cuando el usuario lo pida).
