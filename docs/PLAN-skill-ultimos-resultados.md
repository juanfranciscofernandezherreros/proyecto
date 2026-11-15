# Plan: skill `ultimos-resultados`

Petición del 2026-11-15: una skill que consulte los últimos resultados agregados a
`results.results`, para ver de un vistazo qué ha entrado tras una extracción.

## Alcance

- Solo lectura. Una consulta guardada en `sql\consultas\` y una skill que la lanza.
- No toca código Java ni Python, ni el esquema: no cambia ningún requisito del SDD.
- "Agregado" se mide con `results.results.updated_at` (la tabla no tiene fecha de
  alta); hay que comprobar si las recargas repetidas lo reescriben.

## Backlog

- [x] Comprobar cómo se comporta `updated_at` en las recargas (consulta guardada).
- [x] Guardar la consulta `sql\consultas\2026-11-15_2000_ultimos-resultados-agregados.sql`.
- [x] Crear `.claude\skills\ultimos-resultados\SKILL.md`.
- [x] Ejecutar la consulta tal como la lanza la skill y anotar el resultado en el fichero.
- [x] Añadir la skill a la tabla de `CLAUDE.md`.
- [x] Commit + push (pedido por el usuario el 2026-11-15).

### Cambio del 2026-11-15 (20:30): la skill enseña solo la lista de los 50 últimos

El usuario quiere ver la lista de resultados, no el resumen por liga.

- [x] Guardar `sql\consultas\2026-11-15_2030_ultimos-50-resultados-agregados.sql` (una sola tabla, 50 filas).
- [x] Apuntar `.claude\skills\ultimos-resultados\SKILL.md` a la consulta nueva y pedir que enseñe la lista entera.
- [x] Ejecutarla (50 filas) y anotar el resultado en el fichero.
- [x] Commit + push de este cambio (pedido por el usuario el 2026-11-15).
