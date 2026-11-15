---
name: ultimos-resultados
description: Consulta de solo lectura de los últimos resultados agregados a PostgreSQL (results.results) en el proyecto Basketball — resumen por liga con el último partido y la última carga, y la lista de los 40 marcadores más recientes. Usar cuando el usuario pregunte qué resultados han entrado, cuáles son los últimos resultados cargados o agregados, si ya está el partido de ayer o de hoy, o para ver qué ha traído una extracción. Para extraer resultados nuevos usar extraer-resultados o resultados-todas-las-ligas; para un partido que no sale en la web, diagnosticar-partido.
model: haiku
---

# Últimos resultados agregados

Una sola llamada, de solo lectura; requiere Postgres arrancado:

```bash
cd /c/Develop/basketball && docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql/consultas/2026-11-15_2000_ultimos-resultados-agregados.sql
```

La consulta ya está guardada en `sql\consultas\` con su cabecera: no hace falta
guardar otra copia al ejecutarla. Si se cambia el SQL (otro límite, filtrar una
liga), se guarda como fichero nuevo según la regla `consultas-sql`.

## Cómo leerlo

Devuelve tres tablas, con horas de Europe/Madrid:

1. **Reparto de `updated_at`**: casi todas las filas caen en la misma hora. Es lo
   esperado: cada recarga reescribe `updated_at` de toda la liga, así que esa
   columna dice cuándo se cargó la liga, no qué filas son nuevas.
2. **Resumen por liga**: `ultimo_partido` (el más reciente con marcador),
   `ultimos_3_dias` y `ultima_carga`. Una liga en temporada con `ultimo_partido`
   de hace días o con `ultima_carga` de otro día está atrasada.
3. **Los 40 partidos más recientes** con marcador, ordenados por fecha del partido.

"Agregado" se ordena por la fecha del partido (`event_datetime`) porque la tabla no
tiene fecha de alta. Para saber exactamente cuántos partidos entraron en una
extracción, comparar el número de `resultados` por liga antes y después.

## Cómo contarlo

Corto: primero las ligas atrasadas, si las hay, con la skill que lo arregla
(`extraer-resultados` para una, `resultados-todas-las-ligas` para todas); después
los últimos partidos que pida el usuario. No extraer ni corregir nada por
iniciativa propia: solo informar.

Para los partidos jugados que siguen sin resultado, usar
`cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd comprobar"`.
