# Plan: H2H y cuotas de los partidos actuales

Fecha: 2026-11-24. Petición: «no veo nada de H2H y Cuotas en la web». La web ya tiene las
pestañas (desplegadas desde `main`), pero los CSV en disco solo cubren del 5 al 30 de
octubre: ningún partido de noviembre ni de los próximos días tiene H2H ni cuotas.
Alcance acordado: **próximos 7 días y últimos 7 días** (180 partidos según
`sql/consultas/2026-11-24_1200_partidos-h2h-cuotas-recientes.sql`: 55 próximos de
Euroliga y NBA y 125 jugados en 10 ligas).

## Hallazgos

- `basket reextraer` (`scripts/py/extraer/reextraer.py`) reextrae datasets de partidos
  concretos y los manda al launcher, pero no conoce H2H ni cuotas.
- El checkout principal tiene `python-pyppeter` en la rama antigua `KAN-341` (`d8af978`):
  ahí el H2H de un partido no jugado falla («did not expose a player-stats link»). En
  `main` (`e7a7590`) la URL de jugadores se construye y funciona: probado con vyf2I8i5
  (Pelicans–Kings, aún sin jugar): H2H 15 filas y cuotas de 15 casas en ~80 s.
- La NBA no ofrece 1X2: ese CSV sale vacío y no es un fallo.

## Backlog

- [ ] `basket reextraer --dataset h2h-cuotas`: una sola sesión del navegador por partido
      para H2H y los 4 mercados; un CSV vacío de estos datasets cuenta como «sin datos»,
      no como fallo; tests en `tests/test_scripts_py.py`.
- [ ] Checkout principal: `python-pyppeter` a `main` y puntero del superproyecto a `e7a7590`.
- [ ] Extraer los 180 partidos en segundo plano con `--progreso` (se puede retomar).
- [ ] Comprobar en Postgres, Mongo y en el navegador un partido próximo y uno jugado.
- [ ] Evidencia en `docs/VERIFICACION-SDD.md`, `basket verificar` en verde y todo en `main`.

## Ampliación: todos los partidos

Petición: «Quiero que se extraigan todos los H2H y cuotas de los partidos». Según
`sql/consultas/2026-11-24_1400_partidos-todos-h2h-cuotas.sql`: 3533 partidos, 3300 sin
H2H (794 jugados, 133 próximos 14 días, 2372 más adelante). El usuario eligió **los
3300** con **4 navegadores en paralelo** (~28 h). Los lotes A y B se pararon y todo se
repartió en `C:\data\basketball\h2h-cuotas\lista-t1..t4.txt` (progreso-t1..t4).
Notas: la NBA no publica cuotas en Flashscore desde aquí (sale «sin datos»); los
partidos lejanos aún no tienen cuotas y habrá que volver a extraerlas cerca de la fecha.

- [ ] Extraer en 4 lotes en segundo plano. Alcance final pedido por el usuario (tras pasar
      por «todos», «noviembre» y «últimas dos semanas»): **solo Euroliga, jugados en los
      últimos 14 días**, 30 partidos sin H2H (Paso 8 de la consulta 1400), en 2 lotes
      (`lista-e1/e2`). Solo los CSV de H2H y cuotas; el resto ya estaba.
- [ ] Revisar fallos y retomarlos con el mismo `--progreso`.
- [ ] Contar en Postgres y Mongo cuántos partidos tienen H2H y cuotas al terminar.

Fuera de alcance: que el ciclo diario extraiga H2H y cuotas de forma automática.
