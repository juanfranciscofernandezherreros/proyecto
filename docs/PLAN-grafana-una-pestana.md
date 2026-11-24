# Plan: una sola pestaña de Grafana

Fecha: 2026-11-24. Petición: «No me abras 2000000 grafanas, solo necesito un dashboard».

## Hallazgo

`scripts/py/basket.py` (`_asegurar_observabilidad`) abre con `webbrowser.open` el
dashboard `basket-logs` en **cada** ejecución de `basket` que no esté en
`SIN_OBSERVABILIDAD`. Con los 4 lotes de `basket reextraer` lanzados a la vez, más las
tareas programadas y los comandos sueltos, se acumulan pestañas. El dashboard ya muestra
todos los comandos y ejecuciones de las últimas 3 h y se refresca cada 5 s, así que basta
con una pestaña.

## Backlog

- [x] `basket` abre el dashboard solo si no lo ha abierto en las últimas 12 h (marca
      `DATA_DIR\logs\basket\.grafana-abierta`); si no, solo imprime el enlace.
- [x] Tests en `tests/test_scripts_py.py` (`BasketLogsTests`): abre la primera vez, no
      la segunda, vuelve a abrir pasadas 12 h; `BASKET_NO_ABRIR_GRAFANA=1` sigue igual.
- [ ] Evidencia en `docs/VERIFICACION-SDD.md`, `basket verificar` en verde y a `main`.
