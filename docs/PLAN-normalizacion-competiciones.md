# Plan — Normalización de competiciones (slug canónico único)

> **Fecha:** 2026-11-07 · **Relacionado:** [SDD.md](SDD.md) (§3.1 componentes, §5 modelo
> de datos, §8 identidad, §11 riesgos) · [ESPECIFICACIONES.md](ESPECIFICACIONES.md).
> **Estado:** propuesto (sin ejecutar). La verificación se hará siguiendo el SDD.

---

## 1. Problema

La misma liga aparece con **dos slugs distintos** según la sección del pipeline: el
calendario (`fixtures`) usa el slug corto de la URL de Flashscore y el marcador
(`results`) usa el nombre canónico del catálogo.

Evidencia (datos reales, 2026-11-07):

| País | `fixtures.competition` | `results.competition` |
|---|---|---|
| Spain | `acb` (258) | `liga-endesa` (56) |
| Israel | `super-league` (160) | `winner-league` (30) |
| Serbia | — | `superleague` (OK, coincide) |

## 2. Causa raíz

- `LIGAS_BASKET.json` define el nombre **canónico** en `competition`, pero la `resultsUrl`
  usa un slug corto distinto:
  - `ACB` → `competition: liga-endesa`, url `.../spain/acb/...`
  - `WINNER` → `competition: winner-league`, url `.../israel/super-league/...`
- En el scraper [`extract_flashscore_matches.py:70-82`](../python-pyppeter/extract_flashscore_matches.py:70),
  `_canonical_competition_parts` solo devuelve el canónico cuando se escribe bajo
  `.../competitions/<país>/<competición>/`; si no, cae al slug crudo de la URL.
- **RESULTS** pasa por el camino canónico; **FIXTURES** acaba con el slug crudo.

## 3. Consecuencias (según el flujo del SDD §4)

- `fixture` y `result` del mismo `matchId` quedan con competición distinta → el read
  model no clasifica el partido de forma única (relacionado con SDD §11).
- El filtro de competición de la web (`/api/v1/matches/filters`) duplica ligas
  (`acb` + `liga-endesa`, `super-league` + `winner-league`).

## 4. Principio de la solución

**Fuente única de verdad del par `(country, competition)`** = los campos `country` +
`competition` de `LIGAS_BASKET.json`. Un único mapa slug-URL → canónico
(`acb→liga-endesa`, `super-league→winner-league`, ampliable) aplicado en todas las ramas.

## 5. Plan por áreas del SDD

### Área: Modelo de datos / Contratos (SDD §5)
- [ ] **5.1** Declarar el mapa canónico en un solo sitio (catálogo `LIGAS_BASKET.json`
  + un diccionario slug→canónico reutilizable por scraper y batches).

### Área: Scraper (SDD §3.1 / §8)
- [ ] **5.2** Hacer que la rama de **FIXTURES** resuelva la competición igual que
  RESULTS (canónico), de modo que el calendario se guarde como `liga-endesa` /
  `winner-league`. *(Raíz del problema.)*

### Área: Orquestador (SDD §3.1, §4)
- [ ] **5.3** Garantizar que extracción y consolidación escriben SIEMPRE bajo
  `.../competitions/<país>/<competición-canónica>/` para ambas secciones.

### Área: Batches — `csv-extra-batch` (SDD §3.1)
- [ ] **5.4** El batch de fixtures graba la competición canónica; como red de
  seguridad, aplicar el mapa de alias si llega un slug crudo.

### Área: Projector (SDD §3.1, §11)
- [ ] **5.5** Reproyectar tras corregir los datos; añadir aviso si `fixture` y
  `result` de un mismo `matchId` difieren en competición.

### Área: Migración de datos (SDD §5; consulta en `sql/consultas/`, marcada ESCRITURA)
- [ ] **5.6** `UPDATE fixtures.fixtures SET competition='liga-endesa' WHERE
  competition='acb'` y `'winner-league' WHERE competition='super-league'`
  (guardar antes de ejecutar; ~258 + ~160 filas) y reproyectar.

### Área: API / Web (SDD §3.1, §6)
- [ ] **5.7** Verificar que `/filters` deja de ofrecer `acb` / `super-league`.
  Opcional: alias de compatibilidad en la API para datos antiguos.

### Área: Observabilidad / Verificación (SDD §9, §12)
- [ ] **5.8** Consulta/panel que liste competiciones con slug no canónico (alerta de
  regresión); verificar que un partido de Spain une `fixture` + `result`.

## 6. Verificación (siguiendo el SDD §12)

1. `fixtures` y `results` muestran el MISMO `competition` por país (solo canónicos).
2. `/api/v1/matches/filters` no incluye `acb` ni `super-league`.
3. Un partido de Spain devuelve `fixture` + `result` con `competition=liga-endesa`.
4. Ningún slug no canónico en `fixtures`/`results` (consulta de regresión 5.8).

## 7. Orden sugerido

5.1 → 5.2 (raíz) → 5.3/5.4 → 5.6 (migración, efecto inmediato en web) → 5.5
(reproyección) → 5.7/5.8 (verificación). La migración (5.6) da resultado visible ya;
el arreglo del scraper (5.2) evita que reincida.
