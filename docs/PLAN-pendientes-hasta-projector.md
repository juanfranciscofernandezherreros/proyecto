# Plan: `basket pendientes` hasta el projector, con los mismos pasos que `resultados-ayer`

Fecha: 2026-11-17

## Objetivo

Que `procesar-pendientes` siga los mismos pasos que `resultados-ayer`: levantar todo
(Grafana, Loki y promtail, Postgres, launcher, runtime, navegador), procesar y
**terminar en el projector**, esperando a que lleve los datos a Mongo y comprobando
partido a partido qué secciones tiene. Las dos skills siguen siendo independientes:
ninguna llama a la otra.

## Situación de partida

- `basket pendientes` (`lanzadores/matchids_pendientes.py`) ya levanta Grafana, Loki
  y promtail (lo hace `basket.py` para todo comando que no esté en `SIN_OBSERVABILIDAD`).
- Asegura `antibloqueo postgres auditoria launcher navegador`, pero **no** `runtime`:
  si el projector está parado, lo cargado en Postgres no llega a Mongo y nadie avisa.
- Al terminar solo imprime el recuento de `PROCESAR_MATCHIDS_<run_id>.csv`.

## Áreas SDD

- Pipeline (`scripts\py`): cambio en el lanzador; `procesar_matchids.py` no cambia.
- Documentación operativa: skill `procesar-pendientes`, ayuda de `basket`.
- Verificación: gate `scripts\py\verificar.py` y evidencia en `docs\VERIFICACION-SDD.md`.

## Diseño

1. `ensure(...)` añade `runtime` (Mongo, projector, API y web), igual que `resultados-ayer`.
2. Tras `procesar_matchids.py`, se lee el `PROCESAR_MATCHIDS_*.csv` de esta ejecución
   (el más reciente creado después de empezar) y se toman los `COMPLETED`.
3. Espera `CICLO_ESPERA_CUADRE` (90 s) a que el projector los lleve a Mongo.
4. Lee Mongo con `cuadrar_dia.leer_mongo` y por cada partido imprime `OK`,
   `FALTAN <secciones>` o `NO ESTA EN MONGO`, y la línea
   `En Mongo (projector): n de m con todas las secciones`.
5. Código de salida: el de `procesar_matchids`, o 1 si algún partido no está en Mongo.
   Las secciones que faltan no hacen fallar: pueden ser `NO_PUBLICADO` / `VACIO`.

## Backlog

- [x] `matchids_pendientes.py`: añadir `runtime` a `ensure`.
- [x] `matchids_pendientes.py`: esperar al projector y comprobar Mongo (pasos 2–5).
- [x] `basket.py`: ayuda de `pendientes` menciona "hasta el projector".
- [x] Skill `procesar-pendientes`: reescrita con la misma estructura que `resultados-ayer`
      (comando, "Hace, en este orden", "Qué decir al terminar", tabla de fallos), sin
      mandar a otras skills.
- [x] Verificación: compilar, prueba de la comprobación en Mongo con partidos reales y
      gate `verificar.py` en verde; evidencia en `docs\VERIFICACION-SDD.md`.
      (Falta la ejecución completa con el código nuevo: la de los 97 partidos arrancó antes.)
- [x] Commit + push.
