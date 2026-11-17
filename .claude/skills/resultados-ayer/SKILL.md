---
name: resultados-ayer
description: Procesa los resultados de ayer de todas las ligas hasta el projector, sin preguntar nada — genera RESULTS_YESTERDAY_<fecha>.csv con los RESULTS ya extraídos, lo carga en PostgreSQL, espera al projector y comprueba en MongoDB (lo que escribe el projector) que cada partido está con su marcador; no abre la web. Usar cuando el usuario pida los resultados de ayer, el RESULTS_YESTERDAY, procesar el CSV de ayer o llevar los resultados de ayer hasta el projector. Para extraer resultados nuevos de Flashscore, resultados-todas-las-ligas.
---

# Resultados de ayer hasta el projector

Sin preguntar nada al usuario, lanzar en segundo plano (tarda unos minutos) y redirigir
la salida a un fichero del directorio temporal de la sesión:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd resultados-ayer"
```

Hace, en este orden:

1. Genera `C:\data\basketball\reports\resultados-ayer\RESULTS_YESTERDAY_<AAAAMMDD>.csv`
   con los partidos de ayer (hora de Madrid) del último `RESULTS_*.csv` de cada liga.
   No extrae de Flashscore.
2. Lo carga en Postgres por el launcher, una liga cada vez (las partes quedan en
   `resultados-ayer\<AAAAMMDD>\`, fuera de `competitions\`).
3. Espera 90 s (`CICLO_ESPERA_CUADRE`) a que el projector lo lleve a Mongo.
4. Comprueba en Mongo (lo que escribe el projector) que cada partido está con su marcador. No abre la web.

Otra fecha: `basket resultados-ayer 2026-11-16`. Solo el CSV: `--solo-csv`.

## Qué decir al terminar

El total y el reparto por liga, la ruta del CSV, cuántas ligas se cargaron
(`PROCESAR ... -> COMPLETED`) y la línea `En Mongo (projector): n de m con su marcador`.
Código 0 si todo está en Mongo; 1 si algo falló.

| Sale | Qué hacer |
|---|---|
| Una liga con 0 partidos que sí jugó | Su RESULTS es de antes del final del día: `basket resultados ALL` y repetir |
| `PROCESAR ... -> FAILED` | Ver la carga en `public.batch_launch_request` (skill `diagnosticar-partido`) |
| `NO ESTA EN MONGO` / `MARCADOR DISTINTO EN MONGO` | Esperar un minuto más y repetir; si sigue, skill `diagnosticar-partido` |

Las jugadas y estadísticas de esos partidos no van aquí: las cargan los pendientes.

## Relacionado

- Lógica: `scripts\py\lanzadores\resultados_ayer.py`. Plan: `docs\PLAN-resultados-ayer.md`.
- Cuadre con fixtures y secciones: skill `cuadrar-partidos-dia`.
