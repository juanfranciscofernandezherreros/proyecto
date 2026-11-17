---
name: resultados-ayer
description: Trae los resultados de ayer de todas las ligas hasta el projector, sin preguntar nada — primero hace el cuadre diario (fixtures / Mongo) y, si ya están todos, termina sin extraer; si no, extrae de Flashscore los resultados de las ligas con pendientes con el scraper python-pyppeter (Selenium + Edge), genera RESULTS_YESTERDAY_<fecha>.csv con los partidos de ayer, lo carga en PostgreSQL por el launcher, espera al projector y comprueba en MongoDB que cada partido está con su marcador; la salida se ve en vivo en el dashboard basket-logs de Grafana. Usar cuando el usuario pida los resultados de ayer, el RESULTS_YESTERDAY, procesar el CSV de ayer o llevar los resultados de ayer hasta el projector. Para todos los resultados de la temporada de todas las ligas, resultados-todas-las-ligas.
---

# Resultados de ayer hasta el projector

Sin preguntar nada al usuario, lanzar en segundo plano (segundos si ya está todo; si no, ~40 s por liga a extraer) y
redirigir la salida a un fichero del directorio temporal de la sesión. Antes, comprobar
que no hay otro `resultados-ayer` en marcha: dos a la vez se pisan.

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd resultados-ayer"
```

Hace, en este orden:

1. `basket` levanta Grafana, Loki y promtail, y duplica la salida en
   `C:\data\basketball\logs\basket\resultados-ayer_<AAAAMMDD_HHMMSS>.log`. Imprime el
   enlace `Logs en vivo:` al dashboard `basket-logs` (http://localhost:8084/d/basket-logs).
2. Asegura antibloqueo, Postgres, launcher, runtime (Mongo, projector, API y web) y
   navegador.
3. **Cuadre previo** (lógica de `cuadrar_dia`): partidos de ese día en `fixtures` y en
   Mongo, y el `RESULTS_YESTERDAY` anterior si existe. Si todos están en Mongo con su
   marcador, imprime `Ya estan todos los partidos ...` y termina con código 0 sin
   extraer. Si fixtures no tiene partidos ese día o el cuadre falla, extrae todas.
   Las secciones (jugadas, estadísticas) no cuentan aquí.
4. Extrae de Flashscore los resultados de cada liga con pendientes con el scraper
   `python-pyppeter\flashscore.py competition results` (Selenium + Edge; unos 40 s por
   liga). Va a `reports\resultados-ayer\<AAAAMMDD>\extraccion\<LIGA>\`, sin tocar
   `competitions\`. Una liga que falla queda `FALLO` y se sigue.
5. Se queda con los partidos de ayer (hora de Madrid) y los junta en
   `C:\data\basketball\reports\resultados-ayer\RESULTS_YESTERDAY_<AAAAMMDD>.csv`
   (las ligas no extraídas conservan sus filas anteriores).
6. Lo carga en Postgres por el launcher, una parte por liga
   (`resultados-ayer\<AAAAMMDD>\RESULTS_<ts>_<pais>_<competicion>.csv`). Una liga que
   tarda más de 3 minutos se da por fallida.
7. Espera 90 s (`CICLO_ESPERA_CUADRE`) a que el projector lo lleve a Mongo.
8. Comprueba en Mongo que cada partido está con su marcador. No abre la web.

Otra fecha: `basket resultados-ayer 2026-11-16`. Solo extraer y generar el CSV:
`--solo-csv`. Saltarse el cuadre previo y extraer todas: `--forzar`.

## Qué decir al terminar

Si salió `Ya estan todos`: que ya estaban, cuántos partidos y que no se extrajo nada.
Si no:
El total y el reparto por liga, la ruta del CSV, cuántas ligas se cargaron
(`PROCESAR ... -> COMPLETED`) y la línea `En Mongo (projector): n de m con su marcador`.
Código 0 si todo está en Mongo; 1 si algo falló.

| Sale | Qué hacer |
|---|---|
| `[FALLO] [LIGA]` en la extracción | Ver el log; repetir, o `basket resultados <LIGA>` (skill `extraer-resultados`) |
| Una liga con 0 partidos que sí jugó | Flashscore aún no lo tenía: repetir más tarde |
| `PROCESAR ... -> FAILED` o tiempo agotado | Ver la carga en `public.batch_launch_request` (skill `diagnosticar-partido`) |
| `NO ESTA EN MONGO` / `MARCADOR DISTINTO EN MONGO` | Esperar un minuto más y repetir; si sigue, skill `diagnosticar-partido` |
| `AVISO: Grafana o promtail no arrancaron` | El comando sigue; los logs solo quedan en el fichero |

Las jugadas y estadísticas de esos partidos no van aquí: las cargan los pendientes.

## Relacionado

- Lógica: `scripts\py\lanzadores\resultados_ayer.py`. Planes:
  `docs\PLAN-resultados-ayer.md`, `docs\PLAN-logs-basket-en-grafana.md`,
  `docs\PLAN-resultados-ayer-cuadre-previo.md`.
- Cuadre con fixtures y secciones: skill `cuadrar-partidos-dia`.
