# Plan: aviso a Telegram por cada partido procesado

Pedido el 2026-11-17. Hasta ahora `basket pendientes` avisa al empezar
(«⏳ Pendientes: N partidos…») y al terminar (`RESUMEN`); entre medias, con 54 partidos
y ~2 min por partido, no hay forma de saber cuántos quedan sin mirar el log.

## Backlog

- [x] 1. `procesar_matchids.py`: tras cada partido (no los omitidos por la auditoría),
  enviar a Telegram una línea `✅ 3/54 · Home - Away (pais/competicion) · quedan 51`, o
  con `❌` y el motivo recortado si falló. «Quedan» son los partidos de la tanda aún sin
  procesar. Si Telegram falla, avisa en el log y sigue. Test del texto y del envío.
- [x] 2. Tests, `basket verificar` en VERDE, evidencia en `docs/VERIFICACION-SDD.md`,
  `index.html` y commit + push.
- [ ] 3. Añadir el mensaje a la tabla de Telegram del artículo del blog (rama, PR, checks,
  merge, comprobar la publicación).

## Resultado (2026-11-17)

- Tests del repo 66 OK (`test_pendientes_avisa_de_cada_partido_y_cuantos_quedan`);
  `basket verificar` VERDE. `index.html` muestra el mensaje en «Observabilidad y avisos».
- El `pendientes` que ya estaba en marcha cargó el código antes del cambio: los avisos por
  partido empiezan en la siguiente ejecución.
