# Plan: enviar al bot de Telegram cada CSV que se procesa

Fecha: 2026-11-17

## Objetivo

Que cada CSV que procesa el launcher (resultados, jugada a jugada, estadísticas,
fixtures…) llegue al bot `@MiGrafanaDashboardOutOfHome_bot` como documento, con su
estado (`COMPLETED` / `FAILED`), su tipo de batch y, si falló, el error.

## Diseño

Todos los caminos de carga (`resultados-ayer`, `pendientes`, `run_all_csv_batches`,
`reextraer`…) acaban en el launcher, que deja una fila por CSV en
`public.batch_launch_request`. Por eso no se toca ningún importador: un **vigilante**
lee esa tabla y envía lo que termina, venga de donde venga.

- `scripts\py\monitor\telegram_csv.py`: cada `TELEGRAM_INTERVALO` s (10) consulta las
  filas con `finished_at` posterior a la última enviada y, por cada una, `sendDocument`
  con el CSV y un pie (estado, batch, fichero, carpeta, hora, error). Si el fichero no
  existe o pasa de 50 MB (límite de Telegram), manda solo el mensaje.
- Estado en `DATA_DIR\state\telegram_csv.json` (último `finished_at` enviado). La
  primera vez empieza en "ahora": no reenvía el histórico.
- Envío con `curl.exe` (urllib de Python se quedaba colgado contra api.telegram.org
  en esta máquina; curl responde en 0,5 s).
- Opciones: `--prueba` (mensaje de prueba) y `--una-vez` (una pasada y termina).
- Configuración: `TELEGRAM_BOT_TOKEN` y `TELEGRAM_CHAT_ID` vacíos en
  `config\basketball.env`; los valores reales solo en `config\basketball.local.env`
  (ignorado por git). Sin ellos el servicio queda desactivado y no falla nada.
- `asegurar.py`: servicio `telegram` (proceso en segundo plano como `antibloqueo`);
  `launcher` depende de él, así que cualquier comando que cargue CSV lo levanta.
- Comando `basket telegram [prueba|una-vez]`.

## Áreas SDD

- Pipeline/arranque (`scripts\py`): servicio nuevo en `asegurar.py`, comando en `basket.py`.
- Observabilidad: aviso fuera de casa de cada carga.
- Seguridad: el token no se versiona.
- Verificación: tests, gate `verificar.py`, evidencia en `docs\VERIFICACION-SDD.md`.

## Backlog

- [x] Claves `TELEGRAM_*` vacías en `config\basketball.env`; token y chat_id reales en
      `config\basketball.local.env` (comprobar que git lo ignora).
- [x] Consulta del vigilante guardada en `sql\consultas\`.
- [x] `scripts\py\monitor\telegram_csv.py` (pie, envío, estado, `--prueba`, `--una-vez`).
- [x] `asegurar.py`: servicio `telegram`; `launcher` depende de él.
- [x] `basket.py`: comando `telegram`.
- [x] Tests del pie y de la lectura de filas.
- [x] Prueba real: `basket telegram prueba` llega al móvil y un CSV procesado llega como documento.
- [x] Gate `verificar.py` en verde y evidencia en `docs\VERIFICACION-SDD.md`.
- [x] Commit + push (sin el token).

## Cambio 2026-11-17: datos como texto, no el fichero

El usuario no quiere el fichero adjunto, solo los datos. `enviar` manda el pie y las
filas del CSV como texto (`sendMessage`, HTML, bloque `<pre>` con la cabecera de
columnas repetida), partido en mensajes de hasta 4096 caracteres y como mucho
`TELEGRAM_MAX_MENSAJES` (5); el último avisa de las filas que quedan sin enviar.

- [x] `mensajes()` y `leer_lineas()` en `telegram_csv.py`; sin `sendDocument`.
- [x] `TELEGRAM_MAX_MENSAJES=5` en `configasketball.env`.
- [x] Tests: datos en `<pre>` escapados, reparto con máximo, sin fichero.
- [x] Prueba real: `PLAYER_STATS_20261117124906_8SJueQyq.csv` llega como texto en 1 mensaje; vigilante reiniciado.
- [x] Commit + push.

## Cambio 2026-11-17 (2): solo la información del fichero

El usuario no quiere ni el fichero ni su contenido. Un mensaje por CSV con solo:
estado (`✅ COMPLETADO` / `❌ FALLIDO`), nombre del CSV y hora de Madrid en que se procesó.

- [x] `aviso()` y `hora_local()`; fuera `pie()`, `mensajes()`, `leer_lineas()` y `TELEGRAM_MAX_MENSAJES`.
- [x] Tests `TelegramCsvTests` reescritos (50 tests OK).
- [x] Vigilante reiniciado (12:54:57); aviso real de `POINT_BY_POINT_20261117125350_8ArlEYR6.csv`.
- [x] Commit + push.

## Skill `aviso-telegram`

- [x] `.claude\skills\aviso-telegram\SKILL.md`: arrancar, comprobar, probar y arreglar el aviso, sin mandar a otras skills.
- [x] Fila en la tabla de `CLAUDE.md`.
- [x] Commit + push.

## Predicción de la jornada al bot

Al publicar una previa (`basket pronostico publicar`), se envía al bot solo la
predicción: título, una línea por partido (hora de Madrid, equipos, ganador previsto y
probabilidad) y el enlace al artículo. Ni introducción ni análisis. Si Telegram falla
o no está configurado, la publicación no falla: solo avisa.

- [x] `telegram_csv.py`: `enviar_texto()` reutilizable y `mensaje_pronostico()`.
- [x] `lanzadores\pronostico.py`: enviar tras publicar.
- [x] Tests del mensaje de predicción.
- [x] Prueba real con el borrador `euroliga-jornada-12-2026-11-17.json`.
- [x] Skill `pronostico-jornada` (paso 4 y qué contar) y evidencia en `VERIFICACION-SDD.md`.
- [x] Commit + push.
