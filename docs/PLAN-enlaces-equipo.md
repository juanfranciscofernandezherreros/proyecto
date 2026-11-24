# Plan: enlaces a la ficha del equipo en actuaciones, remontadas y curiosidades

Fecha: 2026-11-24. Petición: en `/performances`, `/comebacks` y `/curiosities` el
nombre del equipo no enlaza con su ficha (`/teams/:team`).

## Diagnóstico

- `/performances`: la columna «Equipo» es texto plano.
- `/comebacks`: «Ganador» enlaza, pero «Rival» no.
- `/curiosities`: enlazan «Equipos que mejor empiezan/acaban»; no enlazan las rachas,
  los ganadores sobre la bocina ni las tablas de jugadores.
- Los equipos de las estadísticas de jugadores vienen **abreviados** («SAS», «FEN»)
  y la ficha busca por nombre completo: un enlace a `/teams/SAS` saldría vacío.
  En Mongo, `players` está en orden alfabético, no local/visitante; la suma de
  puntos de cada equipo coincide con el marcador en 811 de 878 partidos.
- Efecto colateral: `teamScore`/`opponentScore` de las actuaciones salen siempre
  `null` porque comparan la abreviatura con el nombre completo del resultado.

## Backlog

- [x] API: resolver el nombre completo de cada abreviatura por partido (suma de
      puntos más cercana al marcador local/visitante; empate → sin resolver) y
      exponer `teamName`/`opponentTeamName` en las actuaciones (corrige `teamScore`).
- [x] API: `teamName` en `PlayerLine`, `PlayerDoubles` y `HotPlayer` de curiosidades
      (en los agregados, el nombre más frecuente del jugador+abreviatura).
- [x] API: tests unitarios y `mvnw verify` en verde; desplegada en 8082.
- [x] Web: componente `TeamLink` (enlace si hay nombre completo, texto si no) y
      usarlo en actuaciones, remontadas («Rival») y todas las tablas de curiosidades.
- [x] Web: tests y build en verde; desplegada en 8083 y comprobada en el navegador.
- [x] Evidencia en `docs/VERIFICACION-SDD.md` y `basket verificar` en verde.
