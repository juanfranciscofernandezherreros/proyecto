---
name: cuadrar-partidos-dia
description: Cuadra los partidos de un día entre Flashscore, fixtures y Mongo (basket cuadrar, solo lectura). Usar para el cuadre diario.
model: haiku
---

# Cuadrar los partidos de un día

Una sola llamada, solo lectura:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd cuadrar"
```

Con fecha: `basket cuadrar 2026-11-16`. Por defecto, ayer en hora de Madrid.

## De dónde sale cada fuente

| Fuente | Qué se lee |
|---|---|
| Flashscore | El último `RESULTS_*.csv` de cada liga de `LIGAS_BASKET.json` (lo que publicaba Flashscore al extraer) |
| fixtures | `fixtures.fixtures`, por la fecha en `Europe/Madrid` |
| Mongo | `basketball.matches`: marcador de `result` y `availableSections` |

## Dentro del ciclo diario

`basket ciclo-diario` lo lanza dos veces, siempre con este orden:
datos de ayer (`basket datos-ayer`) → **cuadre** → resultados de todas las ligas →
**cuadre** → pendientes (sin repetir los datos de ayer). Antes de cada cuadre espera
90 s (`CICLO_ESPERA_CUADRE`) al projector. La salida queda en el log del ciclo, bajo
`--- Cuadre de ayer ...`; si algo no cuadra se anota `[AVISO]` y el ciclo sigue.

## Antes de ejecutarlo

Si en los **AVISOS** sale que el último RESULTS de una liga es anterior al final del
día, la lista de Flashscore de esa liga puede estar incompleta: extraer antes los
resultados (`basket resultados ALL`, skill `resultados-todas-las-ligas`) y repetir.
Una liga sin jugar desde hace tiempo (fuera de temporada) también da ese aviso; no es
un fallo.

## Cómo leer la salida

Una línea por partido (`OK` o `FALLO`), con el marcador de Flashscore y el de Mongo, y
al final `== RESUMEN ==` con cuántos hay en cada fuente. Código 0 si todo cuadra, 1 si
no. Con `TODO CUADRA` basta con decirlo y dar la tabla de partidos.

| Problema | Qué hacer |
|---|---|
| `no esta en fixtures` | Falta en el calendario: `basket comprobar` / skill `diagnosticar-partido` |
| `no esta en Flashscore` | Partido en fixtures que Flashscore no da como jugado (aplazado o anulado): mirarlo en Flashscore antes de tocar nada |
| `no esta en Mongo` | No ha llegado a la web: skill `diagnosticar-partido` |
| `marcador distinto en Mongo` | Reimportar resultados (skill `procesar-csv-resultados`) y esperar ~1 min al projector |
| `faltan secciones: ...` | Falta detalle: `basket datos-ayer <fecha>` o skill `procesar-pendientes` |

Si hace falta comprobar contra la web de Flashscore en directo, la página de resultados
de cada liga es el `resultsUrl` de `LIGAS_BASKET.json`.

## Relacionado

- Lógica: `scripts\py\lanzadores\cuadrar_dia.py` (tests `CuadrarDiaTests`).
- Plan: `docs\PLAN-skill-cuadrar-dia.md`.
