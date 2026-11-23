# Plan: curiosidades ampliadas, con lo más destacado y las más nuevas primero

Pedido el 2026-11-23 para hacer vídeos: «todas» las ideas propuestas, revisar lo más
destacado y ordenar cronológicamente con las nuevas primero.

Situación de partida:
- `sql/consultas/2026-11-21_1000_curiosidades-cronologicas.sql` (skill `curiosidades`):
  13 tipos, del partido más antiguo al más reciente.
- Ya cubiertas de las ideas: parcial más grande (`racha`), montaña rusa (`igualdad`),
  canasta ganadora (`ultima canasta`), cuarto loco (`cuarto record`).
- Datos (exploración `2026-11-23_1330_curiosidades-ampliadas-exploracion.sql`): el
  jugada a jugada **no trae reloj ni prórrogas**; `stats_player` no distingue titular
  y suplente y casi no tiene `player_id` (jugador = nombre + equipo); `results` solo
  tiene una columna de prórroga.
- Web: la pestaña cronológica («Periódico», `basketball-match-web/src/utils/newspaper.ts`)
  ordena del día más antiguo al más reciente.

## Backlog

- [x] 1. Consulta nueva `2026-11-23_1400_curiosidades-ampliadas.sql` (sin pretemporada NBA, como la API; copia ampliada de
  la del 21/11; la anterior se queda como histórico):
  - Partido: `gano perdiendo 3 cuartos`, `cuarto en blanco` (un equipo con 7 o menos).
  - Jugadores: `tiro perfecto` (8+ tiros sin fallo), `negado` (0 de 8+ triples o 0 de
    10+ de campo), `20-20`, `exhibicion` (20+ rebotes, 15+ asistencias, 8+ triples,
    6+ tapones, 6+ robos), `tiros libres` (15+ sin fallo o 20+ lanzados), `perdidas`
    (10+), `maraton` (48+ minutos), `mejor marca` (máximo de puntos de la temporada
    del jugador, 25+, con 5+ partidos antes), `doble turno` (20+ puntos en dos
    partidos de competiciones distintas en 3 días).
  - Equipos: `racha de victorias` (8.ª, 10.ª, 12.ª… seguidas), `racha cortada` (pierde
    quien llevaba 8+ seguidas), `sorpresa` (gana el que tenía 40+ puntos menos de % de
    victorias, con 6+ partidos cada uno), `back-to-back` (NBA: gana por 15+ jugando el
    día después).
  - Columna `nivel` (3 excepcional, 2 muy destacada, 1 curiosa) para revisar lo más
    destacado; se fija con los datos y se documenta en la cabecera.
  - Orden: **de la más nueva a la más antigua** (fecha y hora del partido descendente).
- [x] 2. Consulta de contexto `2026-11-23_1430_curiosidades-por-liga.sql` para los
  bloques del vídeo que no son de un partido: anotación, triples y libres por partido,
  factor cancha y % de finales de 5 o menos por liga, y «la jornada en números» por día.
- [x] 3. Revisar lo más destacado: ejecutar, comprobar a mano los de nivel 3 contra
  `results` / `stats_player` y ajustar umbrales si salen demasiados o datos raros.
- [x] 4. Skill `curiosidades`: nueva consulta, tipos, nivel, orden de más nueva a más
  antigua, sección «Lo más destacado» y consulta por liga.
- [x] 5. Web: la pestaña «Periódico» muestra primero el día más reciente (y dentro del
  día, el partido más reciente). El guion de vídeo sigue en orden de narración (del
  primer día al último). Tests de `newspaper.ts`.
- [x] 6. `basket verificar` en VERDE, evidencia en `docs/VERIFICACION-SDD.md`, commit +
  push (submódulo web incluido).

No se puede (por los datos): sequías (no hay reloj), suplente decisivo (no hay
titulares), dobles prórrogas (una sola columna de prórroga), «contra todo pronóstico»
con el modelo (solo hay pronósticos de algunas jornadas de Euroliga; se usa `sorpresa`
por % de victorias).

Cambios sobre lo planeado: `mejor marca` pide 30+ puntos y superar el máximo en 8+ (con
25 y 5 salían 107); `doble turno` exige mismo nombre **y** mismo equipo (había
homónimos); se quitó la pretemporada de la NBA (falseaba récords y balances).

Desplegado el 2026-11-23: rama web fusionada en `main` y `basketball-match-web` reconstruido.
