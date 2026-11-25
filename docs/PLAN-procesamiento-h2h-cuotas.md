# Plan: los CSV de H2H y cuotas en la pestaña Procesamiento del partido

Fecha: 2026-11-24. Petición: en http://localhost:8083/matches/UPrFb0b5, pestaña
**Procesamiento**, que aparezcan también los CSV de H2H y cuotas.

## Hallazgo

La pestaña lee `GET /api/v1/matches/{id}/processing` (API,
`PostgresProcessingStatusProvider`), que solo conoce 4 etapas fijas (RESUMEN,
ESTADISTICAS, JUGADORES, PLAY_BY_PLAY). Los CSV de H2H y cuotas sí están en
`public.batch_launch_request` (`batch_type` `h2h` y `odds`, un CSV por mercado) y sus
filas en `h2h.h2h` y `odds.odds` (`market_type`).

## Decisión

Se añaden como lista aparte `extraSteps` (no en `steps`): son opcionales y no deben
activar «Relanzar procesamiento» ni el aviso de orden en partidos sin H2H ni cuotas.

## Backlog

- [x] API: `extraSteps` con 5 filas (H2H, CUOTAS GANADOR, CUOTAS 1X2, CUOTAS TOTAL,
      CUOTAS HANDICAP): CSV más reciente por prefijo de fichero, estado, filas en
      Postgres (`h2h.h2h`, `odds.odds` por `market_type`) y horas. Si falta el esquema,
      0 filas. Test unitario.
- [x] Web: tabla «H2H y cuotas» debajo de la de etapas en la pestaña Procesamiento;
      tipos y test de vitest.
- [x] Compilar (`mvnw package`), desplegar API y web y comprobar UPrFb0b5 en el navegador.
- [x] Evidencia en `docs/VERIFICACION-SDD.md`, `basket verificar` en verde y a `main`.

## Ampliación: sin «Procesamiento incompleto» en partidos sin jugar

Petición: ocultarlo en los partidos que aún no se han jugado (p. ej. jyeyBUmS,
Valencia–Panathinaikos, PROGRAMADO): no tienen resumen, estadísticas, jugadores ni
jugadas porque no se han jugado, y el botón «Relanzar procesamiento» no tiene sentido.

- [x] Web: `puedeRelanzarProcesamiento` (función pura en `utils/processing.ts`) exige que
      el partido esté finalizado (`isMatchFinished`); test de vitest.
- [ ] Desplegar la web y comprobar jyeyBUmS (sin aviso) y un partido jugado incompleto.
- [ ] Evidencia, `basket verificar` en verde y a `main`.
