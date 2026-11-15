# Plan — Comando `basket reextraer <match_id...>`

> **Fecha:** 2026-11-15 · **Relacionado:** [SDD.md](SDD.md) (§4 flujo de datos, §7 operación,
> §11 riesgos), [VERIFICACION-SDD.md](VERIFICACION-SDD.md). **Repo:** raíz (`basketball`).
> **Estado:** ejecutado.

## 1. Problema

Los extractores (`scripts\py\extraer\dataset.py`, `point_by_point.py`) solo trabajan sobre
el último RESULTS de una liga y **saltan** los partidos que ya tienen alguna fila en
Postgres (`ya_importados.py`). No hay forma de volver a extraer partidos concretos cuando
sus datos están mal. El 2026-11-15 hubo que escribir un script aparte para reextraer las
TEAM_STATS de 262 partidos (auditoría, control 15).

## 2. Solución

Un comando que recibe `match_id` y, para cada uno, extrae de Flashscore el dataset pedido
y envía el CSV al launcher, **sin** consultar si ya estaba importado.

```
basket reextraer [--dataset equipo|jugadores|resumen|jugadas|todo] [--fichero lista.txt] <match_id...>
```

- País y competición se leen de `results.results` (y si no, de `fixtures.fixtures`): de
  ahí sale la carpeta de CSV `COMPETITIONS_DIR\<pais>\<competicion>`.
- Por defecto `--dataset todo`. `--fichero` admite un `match_id` por línea (lo que haya
  después de un `|` se ignora, para poder pegar la salida de `psql -At`).
- Un fallo en un partido no detiene los demás; al final imprime `RESUMEN` y devuelve 1 si
  hubo algún fallo.

## 3. Pasos

| Paso | Qué | Fichero | Verificación |
|---|---|---|---|
| 1 | Módulo de reextracción (reutiliza `config`, `launcher.submit_and_wait`, el resolvedor y el scraper) | `scripts\py\extraer\reextraer.py` | Reextrae un partido real por dataset y las filas quedan actualizadas hoy en Postgres |
| 2 | Lanzador y alta en el CLI | `scripts\py\lanzadores\reextraer.py`, `scripts\py\basket.py` | `basket ayuda` lo lista; sin argumentos o con un id inválido devuelve 1 con mensaje |
| 3 | Documentación | `docs\ESPECIFICACIONES.md`, skills `extraer-datos-partido` y `diagnosticar-partido`, `docs\VERIFICACION-SDD.md` | Referencias presentes |

## Backlog

- [x] Leer el CLI `basket`, los extractores y el envío al launcher
- [x] Escribir este plan
- [x] Crear `scripts\py\extraer\reextraer.py`
- [x] Crear el lanzador `scripts\py\lanzadores\reextraer.py` y darlo de alta en `basket.py`
- [x] Probar los errores de argumentos (sin ids, id inválido, dataset inválido)
- [x] Probar una reextracción real de un partido con cada dataset
- [x] Documentar: `ESPECIFICACIONES.md`, skills `extraer-datos-partido` y `diagnosticar-partido`
- [x] Anotar la evidencia en `VERIFICACION-SDD.md`
- [x] Commit + push

## 4. Encaje con el SDD

- §4: no cambia el flujo; usa el mismo camino scraper → CSV → launcher → Postgres.
- §3.2: sin puertos nuevos ni servicios nuevos.
- §11: da una salida operativa a los datos mal cargados, que hasta ahora exigían SQL a mano.

## 5. Fuera de alcance

- No borra filas antiguas: los batches hacen UPSERT, así que las filas que ya no coinciden
  con ninguna nueva siguen ahí (ver `sql\consultas\2026-11-15_1525_limpiar-team-stats-descuadradas.sql`).
- No toca `ya_importados.py` ni el criterio de "partido ya importado".
