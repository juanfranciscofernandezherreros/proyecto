# Plan — Poner en verde los tests de python-pyppeter (CI)

> **Fecha:** 2026-11-08 · **Relacionado:** [SDD.md](SDD.md) (§3.1 scraper, §5 contratos,
> §13 verificación continua), [VERIFICACION-SDD.md](VERIFICACION-SDD.md). **Repo:**
> `python-pyppeter`. **Estado:** propuesto.

## 1. Problema
~9 tests de `python-pyppeter` fallan → CI rojo.

## 2. Categorías (causa raíz)

### A. Reales (fallan también en CI Linux) — hay que arreglarlos
1. **Default de navegador = edge.** `browser_name()` por diseño usa, en ausencia de
   config, **edge** (msedgedriver firmado). Tests que esperan `chrome`:
   `test_browser_defaults_to_chrome_and_rejects_unknown_values`,
   `test_builds_chrome_once_with_shared_options`.
2. **El contrato de `fixtures` incluye `event_datetime`.** `FIXTURE_FIELDS` =
   `(match_id, event_time, home_team, away_team, event_datetime)`, pero estos tests
   usan datos/expectativas sin esa columna:
   `test_converts_flashscore_fixture_to_pipeline_contract`,
   `test_skips_fixture_without_confirmed_start_time` (flashscore_matches),
   `test_accepts_nullable_fields_and_valid_utf8`,
   `test_rejects_duplicate_collection_match_id` (csv_validator).

### B. Solo-Windows (verdes en CI Linux) — hacerlos OS-agnósticos
Asertan semántica POSIX de rutas/URL; en Windows producen `\`:
`test_config_paths_json_uses_effective_data_root`,
`test_posix_default_is_global_user_path_not_repo_relative` (app_paths),
`test_spanish_general_stats_url_can_be_used_directly` (flashscore_cli).

## 3. Cambios
- **3.A1** Actualizar los tests de navegador para el default real (`edge`) o fijar
  `FLASHSCORE_BROWSER` explícito en el test según lo que verifiquen.
- **3.A2** Actualizar expectativas/datos de los tests de fixtures y validador para
  incluir `event_datetime` (alinear con `csv_contracts.FIXTURE_FIELDS`).
- **3.B** Marcar los 3 tests POSIX con `@unittest.skipUnless(os.name == 'posix', ...)`
  (prueban rutas POSIX; en Linux/CI siguen ejecutándose y en verde).
- No se toca código de producción salvo que un test destape un fallo real.

## 4. Verificación
- `python -m unittest discover -s tests` en verde en Windows (los POSIX quedan
  "skipped") — y por tanto en CI Linux (allí sí corren y pasan).
- `scripts/Verificar.ps1` sin cambios (no afecta a runtime).
- Evidencia en `VERIFICACION-SDD.md`.

## 5. Pasos (commit + push por cada uno)
1. Este plan.
2A. Arreglar categoría A (navegador + contrato fixtures).
2B. Arreglar categoría B (skip POSIX).
3. Verificar (unittest).
4. Documentar en `VERIFICACION-SDD.md` + submódulo en `proyecto`.
