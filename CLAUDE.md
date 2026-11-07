# Instrucciones del proyecto Basketball

## Arrancar todo (web + procesamiento de CSV)

Cuando el usuario diga "arranca todo", "arranca la web", "inícialo como siempre"
o equivalente, hay que arrancar **dos cosas** y en este orden. **NO** se lanzan
piezas sueltas con `mvn spring-boot:run` ni con `npm run dev` (eso usa puertos
equivocados: 8080 y 5173).

**1) La web y sus servicios** — stack docker en `local-validation\docker-compose.yml`
(desde `C:\Develop\basketball\local-validation`):

```bash
docker compose up -d --build mongo basketball-match-projector basketball-match-api basketball-match-web
```

**2) El procesamiento de los CSV** — el `csv-batch-launcher` de `csv-extra-batch`
(NO está en el compose). Carga en Postgres los CSV consolidados de
`C:\data\basketball-ready\current`, y desde ahí el projector los pasa a MongoDB.
Arrancarlo desde `C:\Develop\basketball`:

```bash
cmd //c "scripts\arranque\ASEGURAR.bat launcher"
```

### Puertos y flujo

CSV → `csv-batch-launcher` → **Postgres** → `basketball-match-projector` → **MongoDB**
→ `basketball-match-api` → **web**.

- **Web** → http://localhost:8083  (nginx `basketball-match-web`, 80 → 8083; consume la API vía `/api`)
- **API** → http://localhost:8082  (`basketball-match-api`, 8080 → 8082)
- **Projector ("procesar")** → sin puerto; reproyecta Postgres → Mongo cada ~60 s
- **Launcher (carga CSV)** → http://localhost:8088
- **Mongo** → 27017 · **Postgres** → 55432

Postgres, Grafana, Prometheus y Loki suelen estar ya levantados (si no, van en el
mismo compose).

### Verificar

- Web y API: `curl http://localhost:8083/` y `curl http://localhost:8082/actuator/health` → 200.
- Launcher procesando: `docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, exit_code FROM public.batch_launch_request ORDER BY created_at DESC LIMIT 15;"`
  → filas `COMPLETED` / `exit_code = 0`.
- Tras cargar CSV, la web tarda ~1 min en reflejarlo (Postgres → projector → Mongo).

El ciclo diario completo (extraer de Flashscore + procesar) es
`1_EJECUTAR\CICLO_DIARIO.bat`.

Los servicios `*-parser`, `*-persistence`, `csv-watcher`, `csv-match-normalizer` y
`file-event-router` ya no existen (se eliminaron del compose); el procesamiento real
lo hace `csv-extra-batch`.

## Consultas a la base de datos

Toda consulta SQL que se ejecute contra la base de datos del proyecto (PostgreSQL de
`local-validation`, por `docker exec ... psql`, el datasource de Grafana o cualquier otra
vía) se guarda en `sql\consultas\` para poder repetirla más adelante.

- **Un fichero por consulta** (o por grupo de consultas de una misma tarea), con nombre
  `AAAA-MM-DD_HHMM_<tema-en-minusculas>.sql`, por ejemplo
  `2026-11-03_0925_partidos-sin-event-time.sql`.
- **Cada fichero es una guía autoexplicativa**: alguien que no conozca el problema debe
  poder entender, solo leyéndolo, para qué sirve, cuándo usarlo y qué hacer con el
  resultado. Cabecera obligatoria en comentarios SQL:
  ```sql
  -- =============================================================================
  -- TÍTULO CORTO
  -- =============================================================================
  -- Fecha:     2026-11-03 09:25
  -- Tipo:      LECTURA | ESCRITURA
  -- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\<fichero>
  --
  -- PARA QUÉ SIRVE   el problema o la pregunta, con contexto (tablas, columnas, por qué importa)
  -- CUÁNDO USARLA    en qué situación conviene volver a ejecutarla
  -- CÓMO LEER EL RESULTADO  qué significa cada columna y qué valores son buenos o malos
  -- QUÉ HACER DESPUÉS       siguiente paso según el resultado (otra consulta, un script...)
  -- RESULTADO EL <fecha>    lo que devolvió o cuántas filas cambió cuando se ejecutó
  ```
- **Cada consulta dentro del fichero va precedida de un comentario** con el número de
  paso, qué hace y por qué (`-- PASO 1 · ...`). En las de escritura, además: qué filas
  toca, qué condiciones protegen los datos existentes y cómo comprobar el efecto.
- **El SQL exacto que se ejecutó**, listo para volver a lanzarlo tal cual (sin variables
  de shell ni escapes de la línea de comandos).
- **Las de escritura** (`INSERT`, `UPDATE`, `DELETE`, DDL) se marcan como `ESCRITURA`, se
  guardan **antes** de ejecutarlas y llevan, si existe, la consulta de lectura que permite
  comprobar el resultado.
- Las consultas que solo sirven de paso intermedio (por ejemplo, ver la estructura de una
  tabla) pueden agruparse en el fichero de la tarea a la que pertenecen.
