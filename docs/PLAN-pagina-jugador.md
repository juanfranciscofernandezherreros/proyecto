# Plan — Página de jugador (paso 13 de las mejoras de noviembre, primera parte)

> **Fecha:** 2026-11-15 · **Relacionado:** [SDD.md](SDD.md) (§6.1 API REST, §5.2 read model),
> [PLAN-mejoras-2026-11.md](PLAN-mejoras-2026-11.md), [VERIFICACION-SDD.md](VERIFICACION-SDD.md).
> **Repos:** `basketball-match-api`, `basketball-match-web`, raíz. **Estado:** en curso.

## 1. Punto de partida

Ya existe una página básica en `/performances/:playerName`
(`basketball-match-web\src\pages\PlayerPerformancesPage.tsx`): una tabla con una fila por partido,
identificado solo por su `matchId`, sin fecha, sin resultado y sin ningún resumen. Solo se llega a
ella desde el ranking de actuaciones (`PerformancesPage.tsx`); desde la ficha de un partido
(`MatchDetailPage.tsx`) no hay enlace.

En la API, el rendimiento de jugador sale de `MatchServiceImpl.getPlayerPerformances` y
`getTopPlayerPerformances`, expuestos por `MatchController` en `GET /api/v1/matches/performances`.
El DTO es `PlayerPerformanceResponse` en `MatchDtos.java`, y la conversión, en `MatchMapper.java`.

## 2. Qué se añade

1. **Resumen del jugador** arriba: partidos, equipos, promedios (puntos, rebotes,
   asistencias, minutos, valoración), porcentajes de tiro acumulados (campo, 2, 3, libres)
   y mejores marcas (puntos, rebotes, asistencias, valoración) con enlace a su partido.
2. **Historial legible**: cada fila con fecha, competición, rival y resultado del equipo
   del jugador, ordenado del más reciente al más antiguo.
3. **Enlace desde la ficha del partido**: el nombre de cada jugador lleva a su página.

## 3. Cambios

- **API (aditivo, no rompe a la web actual):** `PlayerPerformanceResponse` gana
  `eventDatetime`, `competition`, `teamScore` y `opponentScore`, sacados del documento del
  partido que el servicio ya consulta para el rival. Sin endpoint nuevo.
- **Web:** `src\utils\playerSummary.ts` (cálculo puro, con tests, al estilo de `utils\teamStats.ts`),
  `PlayerPerformancesPage.tsx` (resumen + historial), `MatchDetailPage.tsx` (enlaces), tipos y estilos.

## Backlog

Cada paso se marca `[x]` al quedar hecho y verificado (regla `backlog-de-pasos`).

**API (`basketball-match-api`)**
- [x] Revisar lo que ya existe en API y web.
- [x] Escribir este plan.
- [x] Añadir los cuatro campos a `PlayerPerformanceResponse` en `MatchDtos.java`. (Ya estaba en el árbol de trabajo; revisado.)
- [x] Rellenar los campos en `MatchServiceImpl.java` desde el documento del partido (fecha, competición, marcador del equipo y del rival). (Ya estaba en el árbol de trabajo; revisado.)
- [x] Mapearlos en `MatchMapper.java` (incluido `performancesToPageDto`). (Ya estaba en el árbol de trabajo; revisado.)
- [x] Tests de `MatchServiceImpl` para los campos nuevos, incluido un partido sin partido en Mongo (los campos quedan `null`). `get_top_player_performances_adds_match_date_competition_and_score` y `..._without_match_leaves_context_fields_null`.
- [x] Subir la cobertura de `PostgresProcessingStatusProvider` (tests de pendientes, relanzamiento y lectura de CSV en `PostgresProcessingStatusProviderTest.java`): la cobertura de líneas del conjunto pasa de 61,5 % a 82,14 %.
- [x] `mvnw verify` en verde en `basketball-match-api`: 32 tests, cobertura de JaCoCo cumplida.

**Web (`basketball-match-web`)**
- [ ] `src\utils\playerSummary.ts`: promedios, porcentajes acumulados y mejores marcas, con `playerSummary.test.ts`.
- [ ] `PlayerPerformancesPage.tsx`: bloque de resumen y tabla de historial con fecha, competición, rival y resultado.
- [ ] `MatchDetailPage.tsx`: el nombre de cada jugador enlaza a `/performances/:playerName`.
- [ ] `npm run typecheck` y `npm test` en verde.

**Verificación y cierre (raíz)**
- [ ] Arrancar el stack con la skill `arrancar-web` y abrir la página de un jugador real (con partidos en Mongo) en el navegador.
- [ ] Comprobar que el promedio de puntos del resumen coincide con la media de la tabla de historial para ese jugador (cálculo a mano sobre la respuesta de la API).
- [ ] Registrar la evidencia en `docs\VERIFICACION-SDD.md` y actualizar §6.1 de `docs\SDD.md`.
- [ ] Commit + push por submódulo (API, web) y el puntero en la raíz, con la skill `commit-multirepo`.

## 4. Criterios de aceptación

- La respuesta de `/api/v1/matches/performances` mantiene todos los campos actuales; los cuatro nuevos son opcionales y pueden venir `null`.
- La página de jugador muestra fecha, competición, rival y resultado en cada fila, y el resumen se calcula en el navegador a partir de esos datos.
- Un jugador sin partidos con marcador muestra el historial sin romper la página (sin promedios, o con guion).
- Desde cualquier ficha de partido se llega a la página de cada jugador que aparece en ella.

## 5. Riesgos y decisiones

- **Partidos sin marcador en Mongo**: algunos partidos aún no tienen resultado (ver `ultimos-resultados`). Esas filas no deben entrar en los promedios de resultado ni en las mejores marcas de victoria.
- **Mismo nombre, distinto jugador**: la página agrupa por nombre, como hoy. Se acepta el riesgo y se documenta.
- **Coste de la consulta**: el resumen recorre todos los partidos del jugador. Si tarda demasiado, calcular el resumen en la API en vez de en la web; se decide tras medirlo en el paso de verificación.

## 6. Encaje con el SDD

- §4: no cambia el flujo; solo lectura del read model de Mongo.
- §6.1: el contrato de `/api/v1/matches/performances` crece con cuatro campos opcionales.
- §3.2: sin puertos ni servicios nuevos.

## 7. Fuera de alcance

- Unificar jugadores con el mismo nombre en equipos o ligas distintas (se agrupan por
  nombre, como ya hace la página actual).
- Clasificación y calendario (resto del paso 13).
