---
name: extraer-resultados
description: Extrae los resultados (marcadores y parciales) de una liga de baloncesto o de todas con el scraper de Flashscore y los deja cargados en PostgreSQL (results.results), verificando el resultado. Usar siempre que el usuario pida extraer, actualizar o traer los resultados de la Euroliga, la ACB, la NBA o cualquier otra liga, o pregunte por resultados que aún no están en la base de datos.
---

# Extraer resultados de una liga

Ciclo completo y fijo: comprobar → extraer e importar → verificar en Postgres.
Se hace de una vez, sin pedir permiso para cada paso.

## Ligas

| Code | país / competición | Code | país / competición |
|---|---|---|---|
| EUROLIGA | europe / euroleague | LEGA_A | italy / lega-a |
| ACB | spain / liga-endesa | LNB | france / lnb |
| NBA | usa / nba | BBL | germany / bbl |
| BSL | turkey / super-lig | LKL | lithuania / lkl |
| GBL | greece / basket-league | KLS | serbia / superleague |
| WINNER | israel / winner-league | ALL | todas |

El catálogo real es `LIGAS_BASKET.json`. Si el usuario nombra una liga, usar su
`code`; si no nombra ninguna, preguntar solo si no se deduce del contexto. En las
consultas, sustituir `<competicion>` por el valor de la tabla (p. ej. `euroleague`).

## 1. Comprobar el estado actual

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT max(event_datetime) AS ultimo, count(*) AS total FROM results.results WHERE competition = '<competicion>';"
```

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT f.event_datetime, f.home_team, f.away_team FROM fixtures.fixtures f WHERE f.competition = '<competicion>' AND f.event_datetime < now() AND f.event_datetime > (SELECT max(event_datetime) FROM results.results WHERE competition = '<competicion>') ORDER BY f.event_datetime;"
```

La segunda lista los partidos ya jugados según `fixtures` que todavía no tienen
marcador en `results`: son los que debe traer el scraper. Apuntar el `total`.

Para todas las ligas a la vez sirve `1_EJECUTAR\COMPROBAR_RESULTS_FIXTURES.bat`
(solo lectura; `a_revisar = 0` significa que no falta nada).

## 2. Extraer e importar

Desde bash, con ruta completa (un `cd` previo no llega al `cmd`) y en segundo
plano: cada liga tarda entre 1 y 2 minutos, y `ALL` unos 15.

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\EXTRAER_RESULTADOS.bat EUROLIGA"
```

- Es el envoltorio de `LIGAS_ORQUESTAR.bat <LIGA> results`: asegura antibloqueo,
  Postgres, launcher y navegador; baja la página de resultados de Flashscore;
  genera `RESULTS_<fecha>_<pais>_<competicion>.csv` en
  `C:\data\basketball\competitions\<pais>\<competicion>\` y lo importa con
  `IMPORTAR_RESULTADOS.bat`. No hace falta ningún paso más para que quede en la BD.
- El modo `results` baja la página entera; el límite solo afecta al modo `datos`.
- Debe procesar **solo** la liga pedida. Si aparecen otras (`RESULTS [ACB]`,
  `RESULTS [NBA]`...), el filtro de `scripts\ligas\ORQUESTAR_LIGAS.ps1` está roto o
  hay un `FILTRO_PAIS` / `FILTRO_COMPETICION` en `config\basketball.env`.
- Correcto cuando el resumen final dice `<LIGA> RESULTS extraer OK` y
  `<LIGA> RESULTS importar OK`. El resumen queda también en
  `C:\data\basketball\reports\orchestrator\ligas-orquestar-resumen-<fecha>.csv`.
- No usar `mvn spring-boot:run` ni lanzar piezas sueltas del scraper.

## 3. Verificar y mostrar

Repetir la primera consulta del paso 1: `total` debe haber subido y `ultimo` haber
avanzado. Después, mostrar los partidos nuevos:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT event_datetime, home_team, home_score, away_score, away_team FROM results.results WHERE competition = '<competicion>' ORDER BY event_datetime DESC NULLS LAST LIMIT 15;"
```

Si no entra nada nuevo y el paso 1 mostraba partidos pendientes, revisar la salida
del scraper antes de dar la extracción por buena.

## Notas

- Estos resultados son solo marcador y parciales. Para jugada a jugada y
  estadísticas, skill `extraer-datos-partido`.
- Las consultas ejecutadas se guardan en `sql\consultas\` (regla `consultas-sql`).
  Para Euroliga ya existe `2026-11-14_1355_euroliga-resultados-pendientes.sql`.
- La web tarda ~1 min en reflejar los datos (Postgres → projector → Mongo) y solo
  si el stack está levantado (skill `arrancar-todo`).
- No se hace commit ni push salvo que el usuario lo pida.
