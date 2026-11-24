# Plan: flujo H2H y cuotas desde los CSV existentes hasta la web

Fecha: 2026-11-24. Petición: añadir todo el flujo del H2H de los CSV. Alcance acordado:
**solo los CSV H2H que ya hay en disco** (sin volver a extraer de Flashscore en el
flujo diario) y en un PR aparte del de enlaces a equipos.

## Diagnóstico (`sql/consultas/2026-11-24_1010_h2h-estado.sql`)

| Capa | Estado |
|---|---|
| CSV | 394 `H2H_*.csv` en `C:\data` (276 partidos, del 05/10 al 01/11). Columnas: `match_id, section, date, competition, home_team, away_team, note, home_score, away_score, result_for_section_team, source_url` |
| Launcher → Postgres | `extra-importer` carga en `h2h.h2h` (funcionó el 20/10), pero hoy el schema `h2h` no existe: 0 filas |
| Projector → Mongo | Sin código de H2H (nunca lo tuvo): 0 de 3 533 partidos con `h2h`. El compose ya le pasa `H2H_DB_URL` |
| API | `MatchDocument.h2h` (`List<Map>`) se devuelve tal cual |
| Web | Pestaña «H2H» del partido como tabla en bruto, sin enlaces |

Una misma partida puede tener varios CSV H2H (extraídos en días distintos): se proyecta
solo el más reciente (marca de tiempo del nombre `H2H_<AAAAMMDDhhmmss>_<id>.csv`).

## Backlog

- [x] Cargar en Postgres los 394 CSV con `extra-importer` (`DB_SCHEMA=h2h`, raíz `C:/data`)
      y comprobar filas y partidos con una consulta guardada. (Una JVM por fichero tardaba
      ~10 s/CSV: se cortó y se cargó todo con `--files-from`, ver «Cuotas».)
- [x] Projector: datasource `h2h`, lector del último CSV por partido (si el schema no
      existe, lista vacía sin romper la proyección), campo `h2h` en `MatchDocument`,
      sección `h2h` en `availableSections` y en el `sourceHash`; tests; `mvnw verify`.
- [x] Desplegar el projector y comprobar en Mongo los partidos con `h2h`.
- [x] Web: pestaña «H2H» legible (bloques por sección, resultado V/D, marcador y
      equipos con `TeamLink`); tests y build.
- [x] Desplegar la web y comprobar en el navegador un partido con H2H.
- [x] Evidencia en `docs/VERIFICACION-SDD.md`, `basket verificar` en verde y PR.

## Cuotas (añadido el 2026-11-24 a petición del usuario)

Mismo flujo con los `ODDS_*.csv` existentes (4 mercados, ~1575 CSV, ~275 partidos;
`odds.odds` existía vacía, sin proyección y con la pestaña «Cuotas» en bruto).

- [x] `extra-importer`: varios CSV en un arranque (`--file` repetido o `--files-from`);
      1969 CSV (H2H + cuotas) en 9 s, 0 fallos. Tests del importador (4).
- [x] Corregir `market_type` cortado (`home`/`over`/`asian`) en el importador y en lo
      ya cargado (`sql/consultas/2026-11-24_1110_cuotas-mercado-completo.sql`).
- [x] Projector: datasource `odds`, último CSV por partido y mercado, campo `odds` en
      `MatchDocument` y sección `odds`; tests.
- [x] Web: pestaña «Cuotas» legible (ganador, 1X2, total de puntos y hándicap: mejor
      cuota, probabilidad implícita y línea principal); tests y build.
- [x] Desplegar y comprobar en el navegador.

Añadido durante la implementación: el scraper deja filas desalineadas (eliminatorias con
«Advancing to next round: X» en el hueco de un equipo y el rival en `note`; prórrogas
con el empate reglamentario en los marcadores y el final en `note`). El projector las
corrige (`H2hRows`) y la web traduce las notas.

Fuera de alcance: volver a extraer el H2H y las cuotas en el flujo diario (`extract_flashscore_h2h.py`
existe pero `basket` no lo llama). El launcher usa el jar del `extra-importer` del
checkout principal: hasta recompilarlo allí, las cuotas nuevas se cargarían con el
mercado cortado (el arreglo ya está en `main` de `csv-extra-batch`).
