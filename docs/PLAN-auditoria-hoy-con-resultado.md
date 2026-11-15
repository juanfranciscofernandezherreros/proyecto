# Plan: la auditoría cuenta los partidos de hoy que ya tienen resultado

Petición del 2026-11-15: los resultados cargados hoy no aparecen en pendientes hasta
mañana. Un partido de hoy con marcador en `results.results` ya está terminado, así
que debe contar como elegible.

## Alcance

- Solo `csv-extra-batch\fixtures-processing-audit`: `FixtureProcessingAuditService.toAuditRow`
  y sus tests. Sin cambios de esquema ni de SQL.
- Regla nueva: un partido con fecha de hoy y `resultsPresent = true` se audita como
  los demás. Sin resultado sigue en `HOY_O_FUTURO`. Un partido con fecha futura
  sigue en `HOY_O_FUTURO` aunque tenga resultado.
- Requisito SDD afectado: la auditoría de pendientes (ver `docs\SDD.md`).

## Backlog

- [x] Escribir este plan.
- [x] Revisar `FixtureProcessingAuditServiceTest` (el test `excludesTodayRegardlessOfMatchTime` sigue valiendo: no tiene resultado).
- [ ] Cambiar la condición de `toAuditRow` en `FixtureProcessingAuditService.java`.
- [ ] Añadir tests: hoy con resultado es PENDIENTE; futuro con resultado sigue HOY_O_FUTURO.
- [ ] Ejecutar `mvn test` en `csv-extra-batch\fixtures-processing-audit`.
- [ ] Commit + push en el submódulo `csv-extra-batch` y puntero en el padre.
- [ ] Reiniciar el servicio de auditoría y comprobar que pendientes sube con los partidos de hoy.
