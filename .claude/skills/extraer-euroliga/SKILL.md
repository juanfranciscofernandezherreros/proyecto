---
name: extraer-euroliga
description: Extrae los resultados de la Euroliga (europe/euroleague) con el scraper de Flashscore y los deja cargados en PostgreSQL (results.results), verificando el resultado. Usar siempre que el usuario pida extraer, actualizar o traer los resultados de la Euroliga, o pregunte por resultados de Euroliga que aún no están en la base de datos.
---

# Extraer resultados de la Euroliga

Ciclo completo y fijo: comprobar → extraer e importar → verificar en Postgres.
Se hace de una vez, sin pedir permiso para cada paso.

## 1. Comprobar el estado actual

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT max(event_datetime) AS ultimo, count(*) AS total FROM results.results WHERE competition ILIKE 'euroleague';"
```

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT f.event_datetime, f.home_team, f.away_team FROM fixtures.fixtures f WHERE f.competition ILIKE 'euroleague' AND f.event_datetime < now() AND f.event_datetime > (SELECT max(event_datetime) FROM results.results WHERE competition ILIKE 'euroleague') ORDER BY f.event_datetime;"
```

La segunda consulta lista los partidos ya jugados según `fixtures` que todavía no
tienen marcador en `results`: son los que debe traer el scraper. Apuntar el
`total` para compararlo al final.

## 2. Extraer e importar

Desde bash, con ruta completa (un `cd` previo no llega al `cmd`) y en segundo
plano, porque el scraping tarda 1-2 minutos:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\EXTRAER_RESULTADOS.bat EUROLIGA"
```

- Es el envoltorio de `LIGAS_ORQUESTAR.bat EUROLIGA results`: asegura
  antibloqueo, Postgres, launcher y navegador; baja
  `flashscore.com/basketball/europe/euroleague/results/`; genera
  `RESULTS_<fecha>_europe_euroleague.csv` en
  `C:\data\basketball\competitions\europe\euroleague\` y lo importa con
  `IMPORTAR_RESULTADOS.bat`. No hace falta ningún paso más para que quede en la BD.
- El modo `results` baja la página de resultados entera; el límite solo afecta al
  modo `datos`.
- Debe procesar **solo** `RESULTS [EUROLIGA]`. Si en la salida aparecen otras ligas
  (ACB, NBA...), el filtro de liga de `scripts\ligas\ORQUESTAR_LIGAS.ps1` está roto.
- Correcto cuando el resumen final dice `EUROLIGA RESULTS extraer OK` y
  `EUROLIGA RESULTS importar OK`.
- No usar `mvn spring-boot:run` ni lanzar piezas sueltas del scraper.

## 3. Verificar y mostrar

Repetir la primera consulta del paso 1: el `total` debe haber subido y `ultimo`
haber avanzado. Después, mostrar al usuario los partidos nuevos:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT event_datetime, home_team, home_score, away_score, away_team FROM results.results WHERE competition ILIKE 'euroleague' ORDER BY event_datetime DESC NULLS LAST LIMIT 15;"
```

Si no entra nada nuevo y el paso 1 mostraba partidos pendientes, revisar la salida
del scraper antes de dar la extracción por buena.

## Notas

- Las consultas SQL ejecutadas se guardan en `sql\consultas\` según la norma del
  proyecto.
- La web tarda ~1 min en reflejar los datos (Postgres → projector → Mongo) y solo
  si el stack está levantado.
- No se hace commit ni push salvo que el usuario lo pida.
