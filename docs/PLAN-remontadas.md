# Plan — Pantalla de grandes remontadas

> **Fecha:** 2026-11-20 · **Relacionado:** [SDD.md](SDD.md) (§6.1 API REST, §5.2 read model),
> [VERIFICACION-SDD.md](VERIFICACION-SDD.md),
> consulta [2026-11-20_1000_partidos-ganados-tras-gran-remontada.sql](../sql/consultas/2026-11-20_1000_partidos-ganados-tras-gran-remontada.sql).
> **Repos:** `basketball-match-api`, `basketball-match-web`, raíz. **Estado:** hecho.

## 1. Qué se quiere

Una pantalla con los partidos que ganó un equipo que llegó a ir perdiendo por mucho
(por defecto, 15 puntos o más), ordenados de mayor a menor remontada. Es lo mismo que la
consulta SQL de Postgres, pero calculado en la API sobre el read model de Mongo, que es
de donde lee la web.

## 2. Definición

- **Ganador:** el de `result` (marcador final, incluye prórrogas). Empates o sin marcador: fuera.
- **Desventaja máxima:** el mayor `marcador rival − marcador ganador` en las jugadas de
  `match_point_by_point` (cuartos 1 a 4, ordenados por cuarto y secuencia).
- **Peor momento:** cuarto y marcador en que se dio esa desventaja (el primero si se repite).
- **Prórroga:** `result.homePeriods` o `awayPeriods` con más de cuatro periodos.

## 3. Cambios

- **API:** paquete nuevo `comeback` con `ComebackCalculator` (cálculo puro),
  `ComebackService` (lee `matches` con marcador y jugadas, y sus `match_point_by_point`),
  `ComebackController` → `GET /api/v1/comebacks?minDeficit=15&competition=&limit=100`
  y el DTO `ComebackResponse`. Endpoint nuevo, no toca los existentes.
- **Web:** tipo `Comeback`, `getComebacks` en `matchesApi.ts`, página `ComebacksPage.tsx`
  en `/comebacks` con filtro de desventaja mínima y competición, y enlace «Remontadas» en la
  cabecera. Cada fila enlaza a la ficha del partido.

## Backlog

**API (`basketball-match-api`)**
- [x] `ComebackCalculator` con tests (gana local, gana visitante, sin desventaja, prórroga, empate/sin marcador). 6 tests.
- [x] `ComebackService` + `ComebackController` + modelo `Comeback` (sirve de respuesta), con tests de filtro, orden y límite. 4 tests.
- [x] `mvnw verify` en verde: 45 tests. La cobertura ya estaba en 0,79 por `prediction` sin tests; se añade `PredictionArticleServiceImplTest`.

**Web (`basketball-match-web`)**
- [x] Tipo, cliente `getComebacks` y test del cliente (`utils/comebacks.test.ts`).
- [x] `ComebacksPage.tsx`, ruta `/comebacks` y enlace en `Header.tsx`.
- [x] `npm run typecheck` y `npm test` en verde (36 tests).

**Verificación y cierre (raíz)**
- [x] Arrancar el stack, abrir `/comebacks` y comprobar que coincide con la consulta SQL: 59/59 iguales (partido, puntos y prórroga); el primero, 76ers - Cavaliers, 29.
- [x] Evidencia en `docs\VERIFICACION-SDD.md`, §6.1 de `docs\SDD.md` y `basket verificar` en verde.
- [x] Commit + push por submódulo (rama `claude/remontadas` en API y web) y el puntero en la raíz.

## 4. Riesgos y decisiones

- **Coste:** el cálculo recorre unas 3.500 páginas de jugadas (888 partidos). Se hace en
  memoria en cada petición; si tarda más de ~1 s, cachear el resultado unos minutos.
- **Marcadores raros** en el jugada a jugada (p. ej. Oldenburg - Hamburg 23-49 en el 3er
  cuarto) se muestran tal cual; revisarlos es tarea de `diagnosticar-partido`.
