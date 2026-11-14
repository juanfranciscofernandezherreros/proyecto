---
name: arrancar-todo
description: Arranca el proyecto Basketball completo (web, API, projector, Mongo y el launcher que carga los CSV) y verifica que funciona. Usar cuando el usuario diga "arranca todo", "arranca la web", "inícialo como siempre", "levanta el proyecto" o equivalente, o cuando haga falta la web o la API y no estén levantadas.
---

# Arrancar todo (web + procesamiento de CSV)

Hay que arrancar **dos cosas**, en este orden. **No** se lanzan piezas sueltas con
`mvn spring-boot:run` ni con `npm run dev`: usan puertos equivocados (8080 y 5173).

## 1. La web y sus servicios

Stack docker de `local-validation\docker-compose.yml`, desde
`C:\Develop\basketball\local-validation`:

```bash
docker compose up -d --build mongo basketball-match-projector basketball-match-api basketball-match-web
```

Postgres, Grafana, Prometheus y Loki suelen estar ya levantados; si no, van en el
mismo compose.

## 2. El procesamiento de los CSV

El `csv-batch-launcher` de `csv-extra-batch` **no está en el compose**. Carga en
Postgres los CSV consolidados de `C:\data\basketball-ready\current`, y desde ahí el
projector los pasa a MongoDB. Desde `C:\Develop\basketball`:

```bash
cmd //c "scripts\arranque\ASEGURAR.bat launcher"
```

## Puertos

| Pieza | Dirección | Detalle |
|---|---|---|
| Web | http://localhost:8083 | nginx `basketball-match-web`, 80 → 8083; consume la API vía `/api` |
| API | http://localhost:8082 | `basketball-match-api`, 8080 → 8082 |
| Projector ("procesar") | sin puerto | reproyecta Postgres → Mongo cada ~60 s |
| Launcher (carga CSV) | http://localhost:8088 | |
| Mongo | 27017 | |
| Postgres | 55432 | |

## Verificar

- Web y API responden 200:

  ```bash
  curl http://localhost:8083/
  ```

  ```bash
  curl http://localhost:8082/actuator/health
  ```

- Launcher procesando (filas `COMPLETED` y `exit_code = 0`):

  ```bash
  docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, exit_code FROM public.batch_launch_request ORDER BY created_at DESC LIMIT 15;"
  ```

- Tras cargar CSV, la web tarda ~1 min en reflejarlo (Postgres → projector → Mongo).

## Relacionado

- Ciclo diario completo (extraer de Flashscore + procesar): `1_EJECUTAR\CICLO_DIARIO.bat`.
- Los servicios `*-parser`, `*-persistence`, `csv-watcher`, `csv-match-normalizer` y
  `file-event-router` ya no existen (se eliminaron del compose); el procesamiento
  real lo hace `csv-extra-batch`.
