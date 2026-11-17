# Plan: `basket datos-ayer` — extraer los datos de los partidos de ayer que hay en `fixtures`

Fecha: 2026-11-17 · Sustituye a la versión anterior de este plan (extractor de
marcadores por día), que no era lo que se pedía.

## 1. Qué se pide

Un comando que, sin intervención, tome **todos los partidos de ayer que hay en
`fixtures`** y extraiga e importe sus datos (resumen, estadísticas de equipo y de
jugadores, jugada a jugada). Sin pasar los `match_id` a mano.

## 2. Qué existe ya

- `basket ids-ayer` → los `match_id` de `fixtures` de ayer (fecha local de Madrid).
- `basket reextraer --fichero F --progreso P` → por cada `match_id` resuelve la URL en
  Flashscore, extrae los cuatro datasets, los envía al launcher e importa. Toma
  país y competición de `results` o, si falta, de `fixtures`. Un fallo no detiene
  los demás y el fichero de progreso permite reanudar.

Faltaba unirlos: el comando nuevo es solo el pegamento.

## 3. Diseño

`basket datos-ayer [AAAA-MM-DD]` (por defecto, ayer en Europe/Madrid):

1. Asegura servicios (antibloqueo, postgres, launcher, navegador).
2. Lee de `fixtures.fixtures` los `match_id` de esa fecha y los guarda, uno por línea,
   en `C:\data\basketball\reports\datos-ayer\ids-<fecha>.txt`.
3. Si no hay ninguno, lo dice y termina.
4. Ejecuta `extraer/reextraer.py --fichero <ids> --progreso <progreso-<fecha>.txt>`
   (dataset `todo`).
5. Imprime el resumen y la ruta del progreso. Repetir el comando reanuda: salta lo
   anotado como OK. Para forzar de nuevo, borrar el fichero de progreso.

## 4. Riesgos

- Que el importador no acepte detalle de un partido que aún no tiene fila en
  `results`. Se comprueba en la prueba real (paso 6); si falla, se añadirá antes
  un paso de resultados.
- Competencia con `basket resultados ALL`: mismo navegador y launcher; no a la vez.

## 5. Backlog

- [x] 1. Lanzador `scripts\py\lanzadores\datos_ayer.py` (pasos 1-5 del diseño).
- [x] 2. Alta en `scripts\py\basket.py` (`datos-ayer`) y en `basket ayuda`.
- [x] 3. Consulta de lectura guardada en `sql\consultas\` con los IDs por fecha.
- [x] 4. Test en `tests\test_scripts_py.py` (validación de fecha y consulta).
- [x] 5. Skill `procesar-pendientes` / `CLAUDE.md`: mencionar `basket datos-ayer`.
- [ ] 6. (en curso, 1/8 partidos completos) Prueba real con 2026-11-16 (8 partidos: Israel 3, NBA 5) y comprobar
      los datos en Postgres.
- [x] 7. `scripts\py\verificar.py` en verde y nota en `docs\VERIFICACION-SDD.md`.
- [x] 5b. `matchids_pendientes.py` ejecuta `datos-ayer` antes de los pendientes (lo usan
      `pendientes`, `ciclo-diario`, `inicio-automatico`, `extraer-todo`); se desactiva con
      `DATOS_AYER=0` / `SKIP_DATOS_AYER=1`; documentado y con test.
- [ ] 8. Commit + push (skill `commit-multirepo`) solo si el usuario lo pide.
