---
name: ultimos-resultados
description: Muestra los 50 últimos resultados agregados a PostgreSQL (results.results) en el proyecto Basketball, con su marcador, en una consulta de solo lectura. Usar cuando el usuario pregunte qué resultados han entrado, cuáles son los últimos resultados cargados o agregados, si ya está el partido de ayer o de hoy, o para ver qué ha traído una extracción. Para extraer resultados nuevos usar extraer-resultados o resultados-todas-las-ligas; para un partido que no sale en la web, diagnosticar-partido.
model: haiku
---

# Últimos resultados agregados

Una sola llamada, de solo lectura; requiere Postgres arrancado:

```bash
cd /c/Develop/basketball && docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql/consultas/2026-11-15_2030_ultimos-50-resultados-agregados.sql
```

Devuelve una tabla con los 50 últimos resultados: `partido` (fecha y hora, en
Europe/Madrid), `liga`, `marcador`, `cargado` y `match_id`.

La consulta ya está guardada en `sql\consultas\` con su cabecera: no hace falta
guardar otra copia al ejecutarla. Si el usuario pide otra cantidad u otra liga, se
guarda el SQL cambiado como fichero nuevo según la regla `consultas-sql`.

## Cómo leerlo

- "Último" es por fecha del partido (`event_datetime`): la tabla no tiene fecha de
  alta.
- `cargado` es `updated_at`, que cada recarga reescribe para toda la liga. Dice
  cuándo se recargó la fila, no cuándo entró por primera vez.

## Cómo contarlo

Enseñar la lista completa de los 50, tal cual, en una tabla: partido, liga y
marcador. No resumirla ni recortarla. Una frase al final si falta algo evidente
(por ejemplo, una liga sin partidos de hoy). No extraer ni corregir nada por
iniciativa propia: solo informar.

## Relacionado

- Resumen por liga (último partido y última carga de cada una):
  `sql\consultas\2026-11-15_2000_ultimos-resultados-agregados.sql`.
- Partidos jugados que siguen sin resultado:
  `cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd comprobar"`.
