---
name: procesar-pendientes
description: Procesa hasta el projector los partidos jugados a los que les faltan jugadas o estadísticas (basket pendientes). Usar cuando pidan procesar o completar los pendientes.
model: haiku
---

# Pendientes hasta el projector

Sin preguntar. Comprobar antes que no hay otro `pendientes` en marcha. Lanzar en
segundo plano (~1 min por partido), con la salida a un fichero del directorio
temporal de la sesión:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd pendientes" > <fichero> 2>&1
```

Al terminar, leer **solo** la línea `RESUMEN:` (`grep "^RESUMEN:" <fichero>`), que
también llega al bot de Telegram, y contarla tal cual. No leer el log entero.

Solo algunos: `pendientes <csv_seleccion> <limite>` (solo límite: `pendientes "" 20`).
Sin el paso previo de datos de ayer: `set SKIP_DATOS_AYER=1` antes del comando.

`FALTAN <secciones>` no es fallo si Flashscore no las publica. Si el `RESUMEN` sale con
❌, leer las líneas `AVISO|ERROR|NO ESTA` del fichero:

| Sale | Qué hacer |
|---|---|
| `n con error` | Cargas del partido: `docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT batch_type, status, left(error,200) FROM public.batch_launch_request WHERE file_path LIKE '%<match_id>%' ORDER BY created_at DESC LIMIT 10;"`; reintentar con `basket reextraer <match_id>` |
| `n de m en Mongo` con n < m | Esperar un minuto y `basket cuadrar`; si sigue, `docker logs --tail 50 local-validation-basketball-match-projector-1` |
| Ver qué no publica Flashscore | `docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT estado, dataset, count(*) FROM fixtures_processing_audit.dataset_unavailable GROUP BY 1,2;"` |
| `ERROR: ...` | El motivo viene en la propia línea |

Lógica: `scripts\py\lanzadores\matchids_pendientes.py` y
`scripts\py\pendientes\procesar_matchids.py`.
