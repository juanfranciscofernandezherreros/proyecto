---
name: arrancar-web
description: Arranca la web, la API y el projector del proyecto Basketball (con Mongo) y, solo si se pide todo, también el launcher que carga los CSV; después verifica que responden. Usar cuando el usuario diga "arranca todo", "arranca la web", "inicia la API", "levanta el projector", "inícialo como siempre", "levanta el proyecto" o equivalente, o cuando haga falta la web o la API y no estén levantadas.
model: haiku
---

# Arrancar la web, el projector y la API

Arrancar **solo lo que el usuario ha pedido**, nada más:

| El usuario pide | Qué se arranca |
|---|---|
| La web, la API, el projector, o cualquier combinación | Solo el paso 1 |
| "Todo", "el proyecto entero", "como siempre", o el procesamiento de CSV | Paso 1 y paso 2 |

El paso 1 levanta siempre juntos web, API, projector y Mongo: la API y el projector
no funcionan sin Mongo, y la web no sirve sin la API. No arrancar el launcher, ni
Grafana, ni ningún otro servicio por iniciativa propia; si parece que hace falta,
decirlo y esperar a que el usuario lo pida.

**No** se lanzan piezas sueltas con `mvn spring-boot:run` ni con `npm run dev`:
usan puertos equivocados (8080 y 5173).

Al terminar, comprobar con una sola llamada:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd estado"
```

Los contenedores tardan unos segundos en responder tras el `up`; si la web o la API
dan `0`, esperar medio minuto y repetir antes de darlo por fallo.

## 1. Web, projector y API

Stack docker de `local-validation\docker-compose.yml`, desde
`C:\Develop\basketball\local-validation`:

```bash
docker compose up -d --build mongo basketball-match-projector basketball-match-api basketball-match-web
```

Postgres, Grafana, Prometheus y Loki suelen estar ya levantados; si no, van en el
mismo compose.

## 2. El procesamiento de los CSV (solo si se pide "todo")

El `csv-batch-launcher` de `csv-extra-batch` **no está en el compose**. Carga en
Postgres los CSV consolidados de `C:\data\basketball-ready\current`, y desde ahí el
projector los pasa a MongoDB. Desde `C:\Develop\basketball`:

```bash
python "scripts\py\arranque\asegurar.py" launcher
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

- Ciclo diario completo (extraer de Flashscore + procesar): `1_EJECUTAR\basket.cmd ciclo-diario`.
- Los servicios `*-parser`, `*-persistence`, `csv-watcher`, `csv-match-normalizer` y
  `file-event-router` ya no existen (se eliminaron del compose); el procesamiento
  real lo hace `csv-extra-batch`.
