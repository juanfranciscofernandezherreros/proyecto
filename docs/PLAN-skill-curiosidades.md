# Plan — Skill `curiosidades` (desde Postgres, en orden cronológico)

> **Fecha:** 2026-11-21 · **Relacionado:** [PLAN-curiosidades.md](PLAN-curiosidades.md) (pantalla
> `/curiosities`), [SDD.md](SDD.md), [VERIFICACION-SDD.md](VERIFICACION-SDD.md).
> **Repos:** raíz y `basketball-match-web`. **Estado:** hecho.

## 1. Qué se quiere

Una skill que cuente curiosidades sacadas directamente de nuestras tablas de Postgres
(`results.results`, `point_by_point.point_by_point_event`, `stats_player.stats_player`),
**ordenadas cronológicamente** (del partido más antiguo al más reciente, fecha de Madrid).

## 2. Decisiones

- **Una sola consulta** de lectura que devuelve una fila por curiosidad con fecha:
  `fecha`, `liga`, `partido`, `final`, `tipo`, `detalle`, `match_id`, ordenada por
  `event_datetime` y, dentro del partido, por tipo. Así la skill hace una única llamada.
- **Mismas reglas que las consultas de curiosidades del 2026-11-20** (puntos de cada canasta
  por diferencia de marcador, rachas «limpias», jugador = nombre + equipo, nulos = 0).
- **Umbrales** para que solo salga lo llamativo: remontada ≥ 15, racha ≥ 15-0, paliza ≥ 35,
  ≥ 15 cambios de líder, partido ganado con la última canasta, triple-doble, 40+ puntos,
  cuarto récord de su competición y partido con más/menos puntos de su competición.
- **Filtros opcionales** con variables de psql (`-v desde=AAAA-MM-DD -v hasta=… -v liga=…`):
  sin ellas el fichero se ejecuta tal cual sobre todo.
- Las curiosidades sin fecha (medias de temporada, prórrogas por liga) quedan fuera: ya están
  en las consultas de rankings y en la pantalla.
- Sin comando `basket` nuevo: la skill es una llamada `docker exec … psql`, como
  `ultimos-resultados`, y es autocontenida.

## Backlog

- [x] Consulta `sql\consultas\2026-11-21_1000_curiosidades-cronologicas.sql` con cabecera.
- [x] Ejecutarla sin filtro y con filtro de liga y fechas; comprobar el orden cronológico y
      contrastar algunas filas con las consultas de rankings del 2026-11-20 (447 filas;
      remontadas 61, prórrogas 54, triples-dobles 13 y 40+ 30, iguales que las de referencia).
- [x] Skill `.claude/skills/curiosidades/SKILL.md` (cuándo usarla, comando, cómo contarlo).
- [x] Evidencia en `VERIFICACION-SDD.md`, `basket verificar` en verde, commit + push.

## 3. Segunda petición (2026-11-21): la web lo redacta como un periódico, en orden cronológico

Pestaña **«Periódico»** en `/curiosities` (web, sobre los mismos datos de la API que el guion
de vídeo: `/api/v1/curiosities` y `/api/v1/comebacks`):

- Una **edición por día** (fecha de Madrid), del día más antiguo al más reciente, con un
  titular de portada (la curiosidad de más peso del día) y una entradilla.
- Dentro del día, una **noticia por partido en orden de hora de inicio**: titular, subtítulo
  (partido, marcador, competición y hora) y crónica (frase de arranque + curiosidades).
- Titular por peso: récord de temporada > 40 puntos > remontada > última canasta >
  triple-doble > racha > paliza > igualdad > cuartos > totales > de principio a fin.
- Botón «Copiar periódico» (texto plano). Lo que no tiene fecha (temporada) no entra.

### Backlog (periódico)

- [x] `utils/newspaper.ts` (reutiliza la recogida de frases de `videoScript.ts`, que ahora guarda un titular con peso por curiosidad) con tests (7; web 63 en total).
- [x] Pestaña «Periódico» con estilo de periódico (cabecera, portada por día, noticias en columnas); `typecheck` y tests en verde.
- [x] Revisar en el navegador con datos reales: 59 ediciones y 219 noticias del 2 de mayo al 20 de noviembre, días en orden y horas en orden dentro de cada día (0 días desordenados); liga-endesa 17 ediciones y 55 noticias; móvil sin desbordar. Tras leerlo: el ganador de la frase de arranque no se repite en la siguiente («Además,»).
- [x] Evidencia, `basket verificar` en verde, commit + push y llevarlo a `main` (web `72b2480`).

## 4. Tercera petición (2026-11-21): guion de vídeo bien redactado con Postgres e internet

Guion escrito a mano (no el automático de la pestaña «Guion de vídeo», que solo puede usar la API)
de la última semana con datos, `docs/guion-video-semana-2026-11-14_20.md`: orden cronológico por
día, locución, indicaciones de imagen, datos de Postgres marcados **[BD]** y contexto de internet
marcado **[web]** con sus fuentes.

### Backlog (guion)

- [x] Consulta de datos de la semana: `sql\consultas\2026-11-21_1100_datos-guion-video.sql` (partidos por día, anotadores, clasificaciones) y las 64 curiosidades de la semana con `2026-11-21_1000_curiosidades-cronologicas.sql -v desde=2026-11-14 -v hasta=2026-11-20`.
- [x] Contexto de internet: crónica Besiktas–Real Madrid (Eurohoops), Grimes 47 con los Lakers (theScore/AP/ABC7), inauguración NBA (ESPN). Cruzado con la base de datos: los 13-2 de los Lakers según la prensa no cuadraban con los 15-6 de Postgres.
- [x] Hallazgo: `results.results` trae la **pretemporada de la NBA** (4-19 oct., liga regular desde el 20/10): `2026-11-21_1130_nba-lakers-partidos-cargados.sql`. Con liga regular, Lakers 13-3 (cuadra con 13-2 antes del Jazz).
- [x] Redactar el guion (≈ 1.400 palabras, 9 min, 8 bloques), repasar cada cifra contra la consulta y corregir cuatro frases que iban más allá de los datos.
- [ ] **Pendiente (no hecho):** los rankings de la API/pantalla (`/api/v1/curiosities`) incluyen la pretemporada de la NBA («mayor remontada de la temporada», etc.). Decidir si se filtra en la API o en la carga.
- [x] Evidencia en `VERIFICACION-SDD.md`, `basket verificar` y commit + push.

## 5. Cuarta petición (2026-11-21): filtrar la pretemporada de la NBA y pronóstico de la Euroliga

### Backlog (pretemporada)

- [x] `RegularSeason` (API): `onlyRegularSeason()` deja fuera los partidos de la NBA anteriores al 20/10/2026 (22:00Z del 19/10); aplicado en `CuriosityService` y `ComebackService`, con tests (`RegularSeasonTest` y los de los dos servicios ampliados). `mvnw verify` en verde, API `06c2b32`.
- [x] Desplegada: el Dockerfile copia `target/app.jar` de la copia principal (estaba desactualizado y la primera imagen salió sin `/comebacks`); compilado el jar y reconstruida. Navegador/curl: 52 remontadas (antes 61, sin las de pretemporada), 0 de NBA anteriores al 20/10, NBA 226 partidos = Mongo de liga regular; mayor remontada: 76ers 29 (22/10).
- [ ] **Pendiente:** el aviso de que el `Dockerfile` depende de un `app.jar` local es una trampa (`basket arrancar` debería compilarlo); proponer que lo haga.
- [ ] **Pendiente:** al empezar otra temporada hay que actualizar la fecha en `RegularSeason.START_BY_COMPETITION`.

### Backlog (pronóstico Euroliga)

- [x] Revisión del pronóstico de la jornada 12: `docs/REVISION-PRONOSTICO-EUROLIGA-J12.md` (6 de 10; causas y propuestas).
- [x] Pronóstico de la jornada 14 (24-25/11) con la skill `pronostico-jornada`: publicado `euroliga-jornada-14-2026-11-24`; calendario contrastado en la web.
- [x] Calibración del modelo (pedida por el usuario): `scripts\py\pronostico\calibrar.py`. La **localía no mejora** (2,0-5,0 igual); el problema era la **escala** (9 → 14: Brier 0,2212 → 0,2158 en 255 partidos). Aplicado en `previa.py` (`ESCALA`, metodología), `SKILL.md`, test nuevo y tests ajustados (68 OK; 2 fallos preexistentes de `BasketLogsTests` porque `local-validation` no está inicializado en el worktree).
- [x] Previa de la jornada 14 regenerada con la escala 14 y actualizada en Mongo (sin reenviar a Telegram).
- [ ] **Pendiente:** el mensaje de Telegram de la jornada 14 lleva las probabilidades antiguas (81,4 % etc.); reenviarlo si el usuario quiere.
- [ ] **Pendiente:** `csv-extra-batch\pronostico\README.md` (módulo Java) sigue diciendo escala 9; revisar si ese módulo aún se usa.
- [ ] Propuestas de mejora del modelo sin hacer: peso de la temporada 80-100 %, localía por liga, rangos de probabilidad (ver `docs/REVISION-PRONOSTICO-EUROLIGA-J12.md`).

### Backlog (pronóstico con información de internet, 2026-11-21)

- [x] Norma nueva en la skill `pronostico-jornada`: buscar bajas y noticias en internet, solo lo que diga la página leída, con fecha y enlace (`sourceUrls` y `sources`); la metodología publicada ya no dice «sin fuentes externas».
- [x] Previa de la jornada 14 con un párrafo «Bajas y noticias» por partido (informes de lesiones de Eurohoops de las jornadas 11, 12 y 13, hasta el 19/11, y la crónica Besiktas–Real Madrid), 5 fuentes, y aviso en la introducción de que no entran en las probabilidades. Las páginas se leyeron una a una; la búsqueda traía datos de otra temporada (2025-26) que se descartaron. Actualizada en Mongo; sin reenviar a Telegram (las probabilidades no cambian).
- [ ] **Pendiente:** releer los informes oficiales de la jornada 14 el 24 y 25/11 (se publican el día del partido) y actualizar las notas.
- [ ] **Pendiente (Telegram):** los avisos por CSV de `resultados-ayer` (≈ 4 por partido, ~125 en 4 horas) entierran los mensajes del pronóstico. Decidir: pausar el vigilante, avisar solo por partido, o mandar el pronóstico a otro chat.
