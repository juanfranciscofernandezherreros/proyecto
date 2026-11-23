---
name: curiosidades
description: Cuenta curiosidades de los partidos (remontadas, rachas, récords, jugadores, rachas de equipo, sorpresas, comparativa de ligas) sacadas de Postgres, de la más nueva a la más antigua y con lo más destacado. Usar cuando pidan curiosidades, datos llamativos o material para un vídeo.
---

# Curiosidades desde la base de datos

Solo lectura; requiere Postgres arrancado (`local-validation-postgres-1`). Dos consultas,
ya guardadas en `sql\consultas\` (no hace falta guardar otra copia):

```bash
cd /c/Develop/basketball && docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql/consultas/2026-11-23_1400_curiosidades-ampliadas.sql
```

```bash
cd /c/Develop/basketball && docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql/consultas/2026-11-23_1430_curiosidades-por-liga.sql
```

La primera da una fila por curiosidad de cada partido; la segunda, los bloques de
contexto (comparativa de ligas y «la jornada en números»). La segunda solo se lanza si
piden un vídeo, un resumen semanal o comparar ligas.

Filtros opcionales, si el usuario los pide (se pasan con `-v` antes del `<`):

- `-v liga=<competition>` (solo la primera): `nba`, `euroleague`, `liga-endesa`, `bbl`,
  `lnb`, `lega-a`, `super-lig`, `superleague`, `lkl`, `basket-league`, `winner-league`.
- `-v desde=AAAA-MM-DD` y/o `-v hasta=AAAA-MM-DD`: fechas de Madrid, ambas incluidas.
  «Ayer», «esta semana», etc. se traducen a fechas a partir de la fecha de hoy.
- `-v nivel=2` o `-v nivel=3` (solo la primera): solo lo destacado.

Si hay que cambiar el SQL (otro umbral, otro tipo), se guarda como fichero nuevo según la
regla `consultas-sql`. Si no responde Postgres:
`cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd ayuda"`; no inventar datos.

## Qué devuelve la primera

Una fila por curiosidad, **de la más nueva a la más antigua** (fecha y hora del partido
descendente; dentro del partido, primero el nivel alto): `fecha`, `nivel`, `liga`,
`partido` (local marcador visitante), `tipo`, `detalle` y `match_id`.

`nivel`: **3** excepcional (récords de la competición, remontadas o parciales de 25+,
50 puntos, 20-20, 10 triples, rachas de 12+ victorias, sorpresas enormes), **2** muy
destacada, **1** curiosa.

Tipos:
- Partido: `remontada` (15+), `racha` (parcial 15-0+), `ultima canasta`, `igualdad`
  (15+ cambios de líder), `de principio a fin`, `paliza` (35+), `cuarto record`,
  `parcial de cuarto` (25+), `cuarto en blanco` (7 o menos en un cuarto), `mas puntos` /
  `menos puntos`, `prorroga`, `gano perdiendo cuartos` (perdió 3 o 4 de los 4).
- Jugador: `triple-doble`, `40 puntos`, `20-20`, `exhibicion` (20+ reb, 15+ ast, 8+
  triples, 6+ tapones o robos), `tiro perfecto` (8+ tiros sin fallo), `negado` (0 de 8+
  triples o 0 de 10+), `tiros libres`, `perdidas` (10+), `maraton` (48+ min),
  `mejor marca` (máximo de la temporada del jugador, 30+), `doble turno` (20+ en dos
  competiciones en 3 días).
- Equipo: `racha de victorias` (8.ª, 10.ª, 12.ª… seguidas), `racha cortada`, `sorpresa`
  (gana el de mucho peor balance; el detalle lleva los dos balances), `back-to-back`
  (NBA, gana por 15+ el segundo día seguido).

## Cómo contarlo

1. **Lo más destacado** primero: una lista corta (5-10) con las de nivel 3 del periodo,
   también de la más nueva a la más antigua, una línea cada una.
2. Después, **todas, de la más nueva a la más antigua**, respetando el orden de la
   consulta: encabezado por día (p. ej. «22 de noviembre») y, dentro, una frase natural
   por partido que junte sus curiosidades (p. ej. «En el Wurzburg 91-96 Vechta, que se
   fue a la prórroga, Vechta firmó un parcial de 17-0 entre el 3º y el 4º cuarto»).
   Marcar con ★ las de nivel 3. No reordenar por liga ni por tipo.
3. Si se pidió un vídeo o resumen semanal: añadir los bloques de la segunda consulta
   («Qué liga anota más», «El factor cancha», «Finales de infarto», «La jornada en
   números») con sus cifras.

- Usar el `detalle` tal cual en cifras; no inventar datos que no estén en las filas.
- Nombres de liga legibles: NBA, Euroliga, Liga Endesa, BBL, LNB, Lega A, Süper Lig,
  Superliga serbia, LKL, Basket League, Winner League.
- Sin filtros salen ~650 filas: si el usuario no ha pedido un periodo, contarlas todas
  sin recortar; si pide «las últimas» o «de esta semana», filtrar con `desde`; si pide
  solo lo importante, `-v nivel=2`.
- Sin filas: decir que no hay curiosidades para ese filtro.
- No extraer, cargar ni corregir nada por iniciativa propia: solo contar.

## Cómo leerlo

- La pretemporada de la NBA (antes del 20/10/2026) no cuenta: Flashscore la mezcla
  con la liga regular. Al empezar otra temporada hay que mover la fecha en las dos
  consultas (y en `RegularSeason` de la API).
- El jugada a jugada no trae prórrogas ni reloj: rachas, remontadas e igualdad miran solo
  los cuatro cuartos; «última canasta» solo sale en partidos sin prórroga. No hay datos
  para sequías (tiempo sin anotar) ni para titulares/suplentes.
- Récords, rachas, balances y mejores marcas son de toda la temporada cargada, aunque se
  filtre por fechas; con empates salen todos. Jugador = nombre + equipo.
- Las curiosidades de jugadores solo salen en partidos con estadísticas cargadas (los
  pendientes aún no las tienen).
- La NBA juega cuartos de 12 minutos y el resto de 10: sus cifras de puntos no se
  comparan con las de otras ligas.
- Un dato raro se revisa con la skill `diagnosticar-partido`.
