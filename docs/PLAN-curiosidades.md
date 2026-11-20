# Plan — Pantalla de curiosidades

> **Fecha:** 2026-11-20 · **Relacionado:** [SDD.md](SDD.md) §6.1, [PLAN-remontadas.md](PLAN-remontadas.md),
> [VERIFICACION-SDD.md](VERIFICACION-SDD.md). Consultas de referencia en `sql\consultas\`:
> `2026-11-20_2230_partidos-con-mas-puntos-por-cuarto.sql`, `2026-11-20_2300_curiosidades-jugada-a-jugada.sql`,
> `2026-11-20_2330_curiosidades-resultados.sql`, `2026-11-20_2345_curiosidades-jugadores.sql`.
> **Repos:** `basketball-match-api`, `basketball-match-web`, raíz. **Estado:** hecho.

## 1. Qué se quiere

Una pantalla `/curiosities` con todos los rankings de esas consultas, calculados en la API
sobre el read model de Mongo (de donde lee la web), con filtro por competición:

- **Partidos (jugada a jugada):** más igualados (cambios de líder y empates), mayores rachas,
  ganados con la última canasta, de principio a fin (por competición y los más ajustados).
- **Marcadores (resultados):** más puntos en cada cuarto, equipos que mejor arrancan y
  acaban, mayores palizas (final y en un cuarto), prórrogas y puntos totales por competición.
- **Jugadores:** dobles-dobles y triples-dobles, triples-dobles uno a uno, jugadores en
  racha y partidos de 40 puntos o más.

Las remontadas ya tienen su pantalla (`/comebacks`); la nueva enlaza a ella.
Las sorpresas por cuotas quedan fuera: no hay cuotas cargadas.

## 2. Decisiones

- **Un solo endpoint** `GET /api/v1/curiosities?competition=` que devuelve todas las secciones:
  todas recorren los mismos partidos, así que se cargan una vez. Caché de 5 minutos por
  competición (los datos solo cambian cuando el projector carga partidos).
- **Mismas reglas que las consultas SQL**, para poder comparar fila a fila: puntos de cada
  canasta por diferencia de marcador (no `*_points_added`, que está mal al empezar cuarto;
  lo arregla otra sesión), RANK con empates en «más puntos por cuarto», mínimo 5 partidos
  por equipo y 8 por jugador, nulos de jugador = 0.
- **Jugador = nombre + equipo** (en Mongo no hay `player_id`; en Postgres casi nunca lo hay).
- **Web:** tres pestañas que cambian sin volver a llamar a la API.

## Backlog

**API (`basketball-match-api`)**
- [x] Modelos de respuesta y `CuriosityCalculator` (cálculo puro por sección) con tests (13).
- [x] `CuriosityService` (carga de Mongo, filtro, caché) y `CuriosityController`, con tests (4).
- [x] `mvnw verify` en verde: 62 tests, cobertura cumplida.

**Web (`basketball-match-web`)**
- [x] Tipos y cliente `getCuriosities`, con test (`utils/curiosities.test.ts`).
- [x] `CuriositiesPage.tsx` con pestañas y filtro, ruta `/curiosities` y enlace «Curiosidades». El menú superior pasa a desplazarse dentro de la cabecera (seis secciones no cabían entre ~700 y ~900 px).
- [x] `typecheck` y tests en verde (43).

**Verificación y cierre**
- [x] Comparar la respuesta de la API con las cuatro consultas SQL (sin filtro): 16/16 secciones iguales fila a fila. Hallazgo: la consulta de jugadores agrupaba por `player_key` y partía a 600 jugadores (solo 950 de 17325 filas tienen `player_id`); se pasa a nombre + equipo en las dos. Los empates se desempatan por nombre en las dos.
- [x] Revisar la pantalla en el navegador: tres pestañas con una sola llamada a la API; filtro liga-endesa → 72 partidos; móvil en fichas sin desbordar.
- [x] Evidencia en `VERIFICACION-SDD.md`, §6.1 de `SDD.md`, `basket verificar` en verde.
- [x] Commit + push por repo y llevarlo a `main` (pedido por el usuario).

**Curiosidades redactadas como texto (2026-11-20, segunda petición)**
- [x] `utils/curiosityTexts.ts`: un párrafo por sección a partir de los datos de la API (nombres de competición legibles, fechas «20 de octubre», números en español; sin datos → sin párrafo), con tests (5; web 50 en total).
- [x] Párrafo encima de cada tabla y pestaña «Resumen» (primera) con todos los textos seguidos; las tablas siguen igual.
- [x] Revisar los textos en el navegador (sin filtro y con euroleague) y `typecheck`/tests en verde. Pulido tras leerlos: empates con el primero, sujeto explícito en «curiosamente», marcador del ganador primero, minutos del cuarto según la liga.
- [x] Evidencia, `basket verificar` en verde y subir a `main`.

**Guion de vídeo por días (2026-11-20, tercera petición)**
- [x] `utils/videoScript.ts`: guion con entrada, un bloque por día (fecha de Madrid) y, dentro, un párrafo por partido con todas sus curiosidades con fecha (remontadas de `/api/v1/comebacks`, rachas, última canasta, igualdad, de principio a fin, cuartos récord, palizas, partidos con más y menos puntos, triples-dobles, 40+); cierre con los datos de temporada sin fecha. Orden cronológico o inverso y versión en texto plano. Con tests (6). Tras leerlo con datos reales: sin repetir el protagonista en frases seguidas («Además,» / «Y también») y cuartos récord seguidos en versión corta.
- [x] Pestaña «Guion de vídeo» en `/curiosities` con selector de orden y botón «Copiar guion».
- [x] Revisar el guion con datos reales: 57 días, 216 partidos y 268 curiosidades sin filtro; liga-endesa 17 días y 55 partidos; copiar funciona; móvil sin desbordar; `typecheck` y 56 tests en verde.
- [x] Evidencia, `basket verificar` en verde y subir a `main`.

