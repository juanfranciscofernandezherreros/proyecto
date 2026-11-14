---
name: normas-basketball
description: Normas de desarrollo del proyecto Basketball. Invocar antes de implementar o revisar cambios de código (Spring Boot/Java, scraper Python, pipeline CSV) para seguir las convenciones del proyecto y el flujo SDD → plan → verificación. Usar cuando se vaya a crear o modificar endpoints, batches, el projector, el scraper o los contratos CSV.
---

# Normas de desarrollo — Basketball

Sigue estas normas al escribir o revisar código en este proyecto. El detalle de
arquitectura está en `docs/SDD.md`; la operación, en `docs/ESPECIFICACIONES.md`.

## Flujo de trabajo (obligatorio para cambios no triviales)
1. **SDD**: localiza el área y requisito afectado en `docs/SDD.md`.
2. **Plan**: si el cambio es grande, escribe un plan por áreas (como
   `docs/PLAN-normalizacion-competiciones.md`).
3. **Implementa** siguiendo las normas de abajo.
4. **Verifica**: ejecuta `scripts/Verificar.ps1` (o `1_EJECUTAR/VERIFICAR.bat`) y,
   si tocaste código, el build/tests del repo (`mvn verify`, `npm run build`,
   `python -m unittest`).
5. **Documenta la evidencia** en `docs/VERIFICACION-SDD.md` (matriz
   intención → cambio → commit → evidencia).

## Java / Spring Boot
- Arquitectura por capas: `controller` → `service` → `repository`. Los controllers
  **no** llevan lógica de negocio ni acceso directo a repositorios.
- Java 21. Mantener el estilo de wiring existente en cada repo (no mezclar).
- Endpoints bajo `/api/<entidad>` (la API usa `/api/v1/matches`). No romper el
  contrato que consume la web.
- Batches **idempotentes**: `INSERT ... ON CONFLICT (match_id) DO UPDATE`.
- Al rellenar campos desde una fuente secundaria, usar
  `COALESCE(NULLIF(x,''), EXCLUDED.x)` para no pisar valores buenos.
- Cada cambio de lógica lleva test (unit y, si aplica, Cucumber API).

## Contratos CSV / datos
- Los contratos CSV están centralizados en `python-pyppeter/csv_contracts.py`:
  la cabecera ES el contrato. Añadir columnas nuevas **al final** para no desplazar
  las existentes, y actualizar los parsers Java que las leen.
- `(country, competition)` tiene una sola verdad: el par canónico de
  `LIGAS_BASKET.json`. Normalizar los slugs de URL de Flashscore al canónico
  (`acb→liga-endesa`, `super-league→winner-league`). No introducir slugs crudos.

## Scraper (Python)
- Reutilizar `parse_flashscore_datetime` para fechas/horas.
- Cargar la config (`EDGEDRIVER_PATH`) antes de usar el navegador; no asumir
  Selenium Manager.

## SQL
- Toda consulta contra la BD se guarda en `sql/consultas/` con la cabecera
  obligatoria (ver `CLAUDE.md`). Las de ESCRITURA se guardan antes de ejecutarse.

## Git
- Multi-repo: cada subproyecto es su propio repo (submódulos en `proyecto`).
- No commitear ni pushear sin que el build/tests pasen (hay hook `.githooks/pre-push`
  y CI en `.github/workflows/ci.yml`). Commit/push solo cuando el usuario lo pida.
