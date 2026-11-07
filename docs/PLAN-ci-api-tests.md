# Plan — Arreglar los tests de la API que no compilan (CI rojo)

> **Fecha:** 2026-11-08 · **Relacionado:** [SDD.md](SDD.md) (§6 interfaces, §13
> verificación continua), [VERIFICACION-SDD.md](VERIFICACION-SDD.md). **Repo:**
> `basketball-match-api`. **Estado:** propuesto.

## 1. Problema
El CI de `basketball-match-api` falla porque los tests **no compilan**: usan firmas
antiguas que ya no existen en el código de producción.

## 2. Causa raíz
- `MatchServiceImplTest` construye `new MatchServiceImpl(repo, pbp, players)` (3 args),
  pero el constructor actual requiere 4 (`+ MongoTemplate`).
- `MatchServiceImplTest` y `MatchControllerTest` llaman `searchMatches(pageable)` (1 arg),
  pero la firma actual es `searchMatches(pageable, query, country, competition, status,
  minPlays, maxPlays)` (7 args), tanto en servicio como en controller.
- El caso de búsqueda del test mockea `matchRepository.findAll(pageable)`, pero el impl
  actual busca con `MongoTemplate` (`count` + `find` con `Criteria`).

## 3. Cambios (área SDD §6 API; no cambia contrato público)
- **3.1** `MatchServiceImplTest`: añadir `MongoTemplate` mock al constructor.
- **3.2** `MatchServiceImplTest.search_matches_paginated_ok`: mockear
  `mongoTemplate.count(any(Query), eq(MatchDocument.class))` y
  `mongoTemplate.find(any(Query), eq(MatchDocument.class))`; llamar `searchMatches`
  con los 7 argumentos (`pageable, null, null, null, null, null, null`).
- **3.3** `MatchControllerTest`: llamar `searchMatches`/el mock con los 7 argumentos.
- No se toca código de producción (solo tests), así que el contrato que consume la web
  no cambia.

## 4. Verificación
- `./mvnw -B test` (o `verify`) en verde en `basketball-match-api`.
- `scripts/Verificar.ps1` sigue VERDE (no hay cambio funcional).
- Evidencia en `VERIFICACION-SDD.md`.

## 5. Pasos (commit + push por cada uno)
1. Este plan.
2. Arreglar los tests (3.1–3.3).
3. Verificar (`mvnw test`).
4. Documentar evidencia en `VERIFICACION-SDD.md` + actualizar submódulo en `proyecto`.
