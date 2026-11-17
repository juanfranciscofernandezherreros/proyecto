---
name: resultados-ayer
description: Guarda en un CSV llamado RESULTS_YESTERDAY_<fecha>.csv los resultados de ayer de todas las ligas, sacados de los RESULTS ya extraídos (no extrae nada). Usar cuando el usuario pida los resultados de ayer en un fichero, el RESULTS_YESTERDAY, o un CSV con los partidos de un día. Para extraer resultados nuevos de Flashscore, resultados-todas-las-ligas.
---

# Resultados de ayer en RESULTS_YESTERDAY

No extrae nada: usa el último `RESULTS_*.csv` de cada liga, que deja
`basket resultados ALL`. Una sola llamada:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd resultados-ayer"
```

Con fecha: `basket resultados-ayer 2026-11-16`. Por defecto, ayer (hora de Madrid).

## Qué genera

`C:\data\basketball\reports\resultados-ayer\RESULTS_YESTERDAY_<AAAAMMDD>.csv`, con las
columnas del RESULTS (`matchId`, equipos, marcador y parciales) y `country` y
`competition` delante. Se sobrescribe si se vuelve a lanzar para el mismo día.

Va fuera de `competitions\` a propósito: así la carga de RESULTS no lo confunde con
un RESULTS de una liga.

## Salida

Una línea por liga con cuántos partidos tiene ese día y de qué RESULTS salen, y el
total con la ruta del fichero. Decir al usuario el total, el reparto por liga y la ruta.

Si una liga tiene 0 partidos y sí jugó, su RESULTS es anterior al final del día:
extraer antes (`basket resultados ALL`) y repetir.

## Relacionado

- Lógica: `scripts\py\lanzadores\resultados_ayer.py`. Plan: `docs\PLAN-resultados-ayer.md`.
- Comprobar que esos partidos cuadran con fixtures y la web: skill `cuadrar-partidos-dia`.
