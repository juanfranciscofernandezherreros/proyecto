---
name: resultados-ayer
description: Resultados de ayer de todas las ligas hasta el projector (basket resultados-ayer). Usar cuando pidan los resultados de ayer o el RESULTS_YESTERDAY.
model: haiku
---

# Resultados de ayer

Sin preguntar. Comprobar antes que no hay otro `resultados-ayer` en marcha. Lanzar en
segundo plano, con la salida a un fichero del directorio temporal de la sesión:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd resultados-ayer" > <fichero> 2>&1
```

Al terminar, leer **solo** la línea `RESUMEN:` (`grep "^RESUMEN:" <fichero>`), que
también llega al bot de Telegram, y contarla tal cual. No leer el log entero.

Otra fecha: `resultados-ayer 2026-11-16`. Extraer todas sin cuadre previo: `--forzar`.

Si el `RESUMEN` sale con ❌, leer las líneas `FALLO|ERROR|NO ESTA|DISTINTO` del fichero:

| Sale | Qué hacer |
|---|---|
| `liga(s) con fallo` | Repetir el comando: solo extrae las ligas que faltan |
| `n de m en Mongo` con n < m | Esperar un minuto y `basket cuadrar`; si sigue, `docker logs --tail 50 local-validation-basketball-match-projector-1` |
| `carga(s) fallida(s)` | `docker exec -i local-validation-postgres-1 psql -U test -d basketball -c "SELECT status, left(error,200) FROM public.batch_launch_request WHERE file_path LIKE '%resultados-ayer%' ORDER BY created_at DESC LIMIT 5;"` y repetir |
| `ERROR: ...` | El motivo viene en la propia línea |

Lógica: `scripts\py\lanzadores\resultados_ayer.py`. Corre sola al iniciar sesión (tarea
"Basketball - Resultados de ayer al iniciar").
