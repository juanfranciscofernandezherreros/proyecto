---
name: estado-del-sistema
description: Da un vistazo completo y de solo lectura al estado del proyecto Basketball — qué contenedores y servicios están levantados, si la web y la API responden, las últimas cargas del launcher, hasta qué fecha llegan los resultados de cada liga y cuántos partidos hay pendientes. Usar cuando el usuario pregunte cómo está todo, si funciona, qué está arrancado, qué falta por procesar, o antes de empezar una tarea que dependa de los servicios.
---

# Estado del sistema

Todo es de solo lectura: no arranca, no para y no modifica nada. Si falta algo, se
dice y se propone la skill que lo arregla; no se arranca por iniciativa propia.

## 1. Contenedores

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Lo esperado con todo arrancado:

| Contenedor | Para qué | Puerto |
|---|---|---|
| `local-validation-postgres-1` | Postgres, fuente de verdad | 55432 |
| `local-validation-mongo-1` | MongoDB, modelo de lectura | 27017 |
| projector (`basketball-match-projector`) | Postgres → Mongo cada ~60 s | sin puerto |
| API (`basketball-match-api`) | REST | 8082 |
| web (`basketball-match-web`) | nginx | 8083 |
| `basketball-grafana`, `basketball-prometheus`, `basketball-loki` | observabilidad | Grafana 8084 |

Si Docker no responde, Docker Desktop está parado: decirlo y parar aquí.

## 2. Servicios que no van en el compose

```bash
for u in "web http://localhost:8083/" "api http://localhost:8082/actuator/health" "launcher http://localhost:8088/actuator/health" "auditoria http://localhost:8090/fixtures-processing-audit/latest" "grafana http://localhost:8084/api/health"; do set -- $u; printf "%-10s %s\n" "$1" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$2")"; done
```

`200` es correcto y `000` significa que no escucha nadie en ese puerto. Si el
launcher devuelve 404 en esa ruta pero el puerto responde, está levantado: lo que
cuenta es que no sea `000`.

## 3. Últimas cargas del launcher

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, exit_code, created_at FROM public.batch_launch_request ORDER BY created_at DESC LIMIT 15;"
```

Buenas: `COMPLETED` con `exit_code = 0`. Fijarse también en la fecha de la más
reciente: si es de hace días, no se está procesando nada.

## 4. Hasta dónde llegan los resultados, por liga

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT r.country, r.competition, count(*) AS partidos, max(r.event_datetime) AS ultimo_resultado, (SELECT count(*) FROM fixtures.fixtures f WHERE f.country = r.country AND f.competition = r.competition AND f.event_datetime < now() AND f.event_datetime > max(r.event_datetime)) AS jugados_sin_resultado FROM results.results r WHERE r.country <> '' AND r.competition <> '' GROUP BY r.country, r.competition ORDER BY r.country, r.competition;"
```

`jugados_sin_resultado` mayor que cero indica una liga atrasada → skill
`extraer-resultados`. Los resultados no se extraen solos: en
`config\basketball.env`, `CICLO_RESULTS` e `INICIO_RESULTS` están a `0`.

## 5. Partidos pendientes de detalle

Si la auditoría respondió en el paso 2:

```bash
curl -s -m 20 http://localhost:8090/fixtures-processing-audit/latest
```

Dar los totales (`totalFixtures`, `eligibleFixtures`, `pendingFixtures`), no volcar
el JSON entero. Si hay pendientes → skill `procesar-pendientes`.

## 6. Verificación del SDD

Solo si web, API, Postgres y Mongo están levantados:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\VERIFICAR.bat"
```

Comprueba que web y API responden, que no hay slugs de competición no canónicos
(`acb`, `super-league`), que los filtros de la API están limpios y que un partido
de `spain/liga-endesa` une calendario y resultado. Código de salida 0 = verde,
1 = rojo.

## Cómo contarlo

Un resumen corto, empezando por lo que no funciona:

1. Qué está caído o falla, y la skill que lo arregla (`arrancar-todo`,
   `extraer-resultados`, `procesar-pendientes`, `diagnosticar-partido`).
2. Qué está bien, en una línea.
3. Los números: último resultado por liga y pendientes.

Las consultas ejecutadas se guardan en `sql\consultas\` (regla `consultas-sql`).
