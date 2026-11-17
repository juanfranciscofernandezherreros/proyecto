---
name: procesar-pendientes
description: Procesa hasta el projector los partidos pendientes del proyecto Basketball, sin preguntar nada — los ya jugados a los que les falta algún dataset (resumen, jugada a jugada, estadísticas de equipo o de jugadores) — levanta Grafana y todos los servicios, lanza la auditoría, hace datos-ayer, extrae de Flashscore e importa en PostgreSQL lo que falta partido a partido, espera al projector y comprueba en MongoDB qué secciones tiene cada partido; la salida se ve en vivo en el dashboard basket-logs de Grafana. Usar cuando el usuario pida procesar los pendientes, completar partidos, ponerse al día de jugadas y estadísticas, o pregunte cuántos partidos faltan o por qué un partido sigue pendiente.
model: haiku
---

# Pendientes hasta el projector

Sin preguntar nada al usuario, lanzar en segundo plano (puede tardar horas: ~1 min
por partido) y redirigir la salida a un fichero del directorio temporal de la
sesión. Antes, comprobar que no hay otro `pendientes` en marcha: dos a la vez se pisan.

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd pendientes"
```

Hace, en este orden:

1. `basket` levanta Grafana, Loki y promtail, y duplica la salida en
   `C:\data\basketball\logs\basket\pendientes_<AAAAMMDD_HHMMSS>.log`. Imprime el
   enlace `Logs en vivo:` al dashboard `basket-logs` (http://localhost:8084/d/basket-logs/basketball-logs-de-basket?orgId=1&from=now-3h&to=now&timezone=browser&var-comando=$__all&var-ejecucion=$__all&var-buscar=&refresh=5s).
2. Asegura antibloqueo, Postgres, auditoría, launcher, runtime (Mongo, projector,
   API y web) y navegador.
3. **Datos de ayer** (`basket datos-ayer`): los datos de los partidos de ayer que hay
   en `fixtures`. Un fallo aquí no para el resto. Se desactiva con `DATOS_AYER=0` o
   `SKIP_DATOS_AYER=1`.
4. **Auditoría** (http://localhost:8090/fixtures-processing-audit): decide qué
   partidos ya jugados están pendientes y qué dataset le falta a cada uno. Imprime
   `pendientes: N` y deja la lista en
   `C:\data\basketball\reports\orchestrator\FIXTURES_PROCESSING_AUDIT_PENDING_<fecha>.csv`.
5. Partido a partido: resuelve la URL de Flashscore y extrae con el scraper
   `python-pyppeter\flashscore.py` (Selenium + Edge) **solo** los datasets que
   faltan. Van a `C:\data\basketball\competitions\<pais>\<competicion>\<match_id>\`.
6. Carga cada CSV en Postgres por el launcher y vuelve a pasar la auditoría, así no
   repite lo ya hecho. Un partido que falla queda `ERROR` y se sigue.
7. Deja el resumen en `C:\data\basketball\reports\orchestrator\PROCESAR_MATCHIDS_<run_id>.csv`
   e imprime `Completados / omitidos / errores`.
8. Espera 90 s (`CICLO_ESPERA_CUADRE`) a que el projector lo lleve a Mongo.
9. Comprueba en Mongo cada partido completado: `OK` (todas las secciones),
   `FALTAN <secciones>` o `NO ESTA EN MONGO`. No abre la web.

Solo una lista de partidos o un máximo: `basket pendientes <csv_seleccion> <limite>`
(solo límite: `basket pendientes "" 20`). Ciclo diario completo de la tarea
programada (pendientes y archivado de CSV): `basket ciclo-diario`.

## Qué decir al terminar

Cuántos pendientes había, la línea `Completados: n; omitidos: n; errores: n`, la
ruta del CSV de resumen y la línea
`En Mongo (projector): n de m partidos; k con todas las secciones`.
Código 0 si todo está en Mongo; 1 si algo falló.

| Sale | Qué hacer |
|---|---|
| `AVISO: [match_id] ...` / `ERROR` en un partido | Ver sus líneas en el log y su carga (consulta 1); reintentarlo solo a él: `basket reextraer <match_id>` |
| `FALTAN <secciones>` en Mongo | Puede que Flashscore no las tenga: consulta 2. Si no aparece ahí, reintentar `basket reextraer --dataset <DATASET> <match_id>` |
| `NO ESTA EN MONGO` | Esperar un minuto y repetir `basket cuadrar`; si sigue, logs del projector: `docker logs --tail 50 local-validation-basketball-match-projector-1` |
| Partidos jugados sin resultado (no entran en la auditoría) | `basket comprobar` (`a_revisar` debe ser 0); si no, `basket resultados <LIGA>` |
| `AVISO: Grafana o promtail no arrancaron` | El comando sigue; los logs solo quedan en el fichero |

Consulta 1 · cargas de un partido en el launcher:

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, exit_code, attempts, finished_at, left(error, 200) AS error FROM public.batch_launch_request WHERE file_path LIKE '%<match_id>%' ORDER BY created_at DESC LIMIT 10;"
```

Consulta 2 · datasets que Flashscore no tiene (no se reintentan en bucle):

```bash
docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT estado, dataset, count(*) AS partidos, max(last_seen) AS ultimo_intento FROM fixtures_processing_audit.dataset_unavailable GROUP BY estado, dataset ORDER BY estado, dataset;"
```

`NO_PUBLICADO`: la fuente no ofrece ese dataset. `VACIO`: la página existe pero no
tiene filas. Para un partido, filtrar por `match_id` (columnas `reason`, `attempts`,
`source_url`).

Los procesos largos escriben mucho: leer solo el final del fichero (`tail -40`) o las
líneas clave (`grep -E "Completados|En Mongo|AVISO|ERROR"`). Las consultas ejecutadas
se guardan en `sql\consultas\`.

## Relacionado

- Lógica: `scripts\py\lanzadores\matchids_pendientes.py` y
  `scripts\py\pendientes\procesar_matchids.py`. Plan:
  `docs\PLAN-pendientes-hasta-projector.md`.
- Consultas guardadas: `sql\consultas\2026-11-03_1200_pendientes-que-se-repiten.sql`,
  `2026-11-03_1650_pendientes-completados-sin-datos.sql`,
  `2026-11-03_1815_registro-datasets-sin-datos.sql`.
