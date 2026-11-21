---
name: curiosidades
description: Cuenta curiosidades de los partidos (remontadas, rachas, finales, palizas, récords, triples-dobles, 40 puntos) sacadas de Postgres, en orden cronológico. Usar cuando pidan curiosidades o datos llamativos.
---

# Curiosidades desde la base de datos

Una sola llamada, de solo lectura; requiere Postgres arrancado
(`local-validation-postgres-1`):

```bash
cd /c/Develop/basketball && docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql/consultas/2026-11-21_1000_curiosidades-cronologicas.sql
```

Filtros opcionales, si el usuario los pide (se pasan con `-v` antes del `<`):

- `-v liga=<competition>`: `nba`, `euroleague`, `liga-endesa`, `bbl`, `lnb`, `lega-a`,
  `super-lig`, `superleague`, `lkl`, `basket-league`, `winner-league`.
- `-v desde=AAAA-MM-DD` y/o `-v hasta=AAAA-MM-DD`: fechas de Madrid, ambas incluidas.
  «Ayer», «esta semana», etc. se traducen a fechas a partir de la fecha de hoy.

La consulta ya está guardada en `sql\consultas\` con su cabecera y admite los filtros
sin cambiarla: no hace falta guardar otra copia. Si hubiera que cambiar el SQL (otro
umbral, otro tipo), se guarda como fichero nuevo según la regla `consultas-sql`.

Si no responde Postgres: `cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd ayuda"`
para ver cómo arrancarlo; no inventar datos.

## Qué devuelve

Una fila por curiosidad, **ya en orden cronológico** (del partido más antiguo al más
reciente; dentro del partido, por tipo): `fecha`, `liga`, `partido` (local marcador
visitante), `tipo`, `detalle` y `match_id`.

Tipos: `remontada` (ganó tras ir 15 o más abajo), `racha` (parcial de 15-0 o más),
`ultima canasta`, `igualdad` (15+ cambios de líder), `de principio a fin` (nunca por
detrás y ganó por 3 o menos), `paliza` (35+), `cuarto record` y `mas puntos` /
`menos puntos` (récords de su competición en la temporada), `parcial de cuarto` (cuarto
ganado por 25+), `prorroga`, `triple-doble`, `40 puntos`.

## Cómo contarlo

- **Siempre en orden cronológico**, del más antiguo al más reciente, respetando el
  orden de la consulta. No reordenar por importancia ni por liga.
- Agrupar por día (encabezado con la fecha, p. ej. «20 de noviembre») y, dentro, por
  partido: una frase natural en español por partido que junte sus curiosidades
  (p. ej. «En el Wurzburg 91-96 Vechta, que se fue a la prórroga, Vechta firmó un
  parcial de 17-0 entre el 3º y el 4º cuarto»). Usar el `detalle` tal cual en cifras;
  no inventar datos que no estén en la fila.
- Nombres de liga legibles: NBA, Euroliga, Liga Endesa, BBL, LNB, Lega A, Süper Lig,
  Superliga serbia, LKL, Basket League, Winner League.
- Sin filtros salen ~450 filas: si el usuario no ha pedido un periodo, contar todas
  igualmente en orden cronológico, sin recortar; si pide «las últimas» o «de esta
  semana», filtrar con `desde`.
- Sin filas: decir que no hay curiosidades para ese filtro (y la última fecha con
  partidos de esa liga si se sabe).
- No extraer, cargar ni corregir nada por iniciativa propia: solo contar.

## Cómo leerlo

- El jugada a jugada no trae prórrogas ni reloj: rachas, remontadas e igualdad miran
  solo los cuatro cuartos; «última canasta» solo sale en partidos sin prórroga.
- Los récords «de la competición» son de toda la temporada cargada aunque se filtre por
  fechas; con empates salen todos.
- La NBA juega cuartos de 12 minutos y el resto de 10: sus récords de puntos no se
  comparan con los de otras ligas.
- Un dato raro se revisa con la skill `diagnosticar-partido`.
