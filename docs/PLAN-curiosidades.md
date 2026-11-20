# Plan — Pantalla de curiosidades

> **Fecha:** 2026-11-20 · **Relacionado:** [SDD.md](SDD.md) §6.1, [PLAN-remontadas.md](PLAN-remontadas.md),
> [VERIFICACION-SDD.md](VERIFICACION-SDD.md). Consultas de referencia en `sql\consultas\`:
> `2026-11-20_2230_partidos-con-mas-puntos-por-cuarto.sql`, `2026-11-20_2300_curiosidades-jugada-a-jugada.sql`,
> `2026-11-20_2330_curiosidades-resultados.sql`, `2026-11-20_2345_curiosidades-jugadores.sql`.
> **Repos:** `basketball-match-api`, `basketball-match-web`, raíz. **Estado:** en curso.

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
- [ ] Modelos de respuesta y `CuriosityCalculator` (cálculo puro por sección) con tests.
- [ ] `CuriosityService` (carga de Mongo, filtro, caché) y `CuriosityController`, con tests.
- [ ] `mvnw verify` en verde (cobertura JaCoCo ≥ 80 %).

**Web (`basketball-match-web`)**
- [ ] Tipos y cliente `getCuriosities`, con test.
- [ ] `CuriositiesPage.tsx` con pestañas y filtro, ruta `/curiosities` y enlace «Curiosidades».
- [ ] `typecheck` y tests en verde.

**Verificación y cierre**
- [ ] Comparar la respuesta de la API con las cuatro consultas SQL (sin filtro).
- [ ] Revisar la pantalla en el navegador (escritorio y móvil, filtro de competición).
- [ ] Evidencia en `VERIFICACION-SDD.md`, §6.1 de `SDD.md`, `basket verificar` en verde.
- [ ] Commit + push por repo y llevarlo a `main` (pedido por el usuario).
