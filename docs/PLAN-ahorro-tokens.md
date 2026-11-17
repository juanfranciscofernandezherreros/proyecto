# Plan: documentar el ahorro de tokens en cada mejora

Fecha: 2026-11-17

## Objetivo

Que cada optimización deje constancia, con cifras medidas (no a ojo), en
`AHORRO-TOKENS.md` en la raíz del proyecto.

## Diseño

- `basket tokens` (`scripts\py\lanzadores\tokens.py`, sin Grafana): mide lo que se
  carga en **cada sesión** (`CLAUDE.md`, `.claude\rules\*.md` y las descripciones de las
  skills que Claude puede invocar) y lo que se carga **al usar** cada skill (su
  fichero). Tokens ≈ caracteres / 4.
- `AHORRO-TOKENS.md`: estado actual (salida de `basket tokens`), registro de mejoras
  (fecha, qué, antes → después, commit) y próximas mejoras.
- `CLAUDE.md`: una línea con la norma (tras cada optimización, `basket tokens` y una
  fila en `AHORRO-TOKENS.md`).

## Backlog

- [x] `scripts\py\lanzadores\tokens.py` y comando `tokens` en `basket.py` (sin observabilidad).
- [x] Tests de la medición.
- [x] `AHORRO-TOKENS.md` con el estado actual, el registro de hoy y las próximas mejoras.
- [x] Norma en `CLAUDE.md`.
- [x] Commit + push.
