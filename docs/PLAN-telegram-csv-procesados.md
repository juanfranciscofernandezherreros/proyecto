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
- [ ] Prueba real (pendiente: el usuario aun no ha escrito al bot, sin chat_id no se puede enviar): `basket telegram prueba` llega al móvil y un CSV procesado llega como documento.
- [x] Gate `verificar.py` en verde y evidencia en `docs\VERIFICACION-SDD.md`.
- [x] Commit + push (sin el token).
