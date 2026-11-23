# Plan: las curiosidades ampliadas en la web

Pedido el 2026-11-23: que las curiosidades ampliadas (649, con nivel y de la más nueva a
la más antigua; `docs/PLAN-curiosidades-ampliadas.md`) aparezcan en la web.

Decisión: el SDD dice que la API solo lee MongoDB. Se sigue el patrón de los pronósticos:
un comando calcula en Postgres con la consulta ya validada
(`sql/consultas/2026-11-23_1400_curiosidades-ampliadas.sql`) y publica el resultado en
Mongo; la API lo sirve y la web lo pinta. Así no se duplica la lógica en Java.

## Backlog

- [x] 1. `basket curiosidades` (`scripts/py/lanzadores/curiosidades.py`): ejecuta la
  consulta 1400 (salida separada por `\x1f`), convierte cada fila en un documento
  (`rank` = posición, `date` ISO, `level`, `competition`, `match`, `type`, `detail`,
  `matchId`) y reemplaza la colección `curiosity_feed` de Mongo. Tests del parseo.
- [x] 2. Encadenarlo al final de `resultados-ayer` (tras los pendientes); si falla,
  `[AVISO]` y no cambia el código de salida.
- [x] 3. API: `GET /api/v1/curiosities/feed?competition=&minLevel=` desde
  `curiosity_feed`, ordenado por `rank` (lo más nuevo primero), con caché de 1 minuto.
  Tests.
- [x] 4. Web: pestaña «Todas» en `/curiosities` (primera y por defecto): lo más
  destacado arriba (nivel 3) y luego todas por día, de la más nueva a la más antigua,
  con filtro de nivel y el filtro de competición de la página. Tests de la utilidad.
- [x] 5. Publicar, reconstruir API y web, comprobar en 8083 (navegador).
- [x] 6. `basket verificar` VERDE, evidencia en `docs/VERIFICACION-SDD.md`,
  `docs/ESPECIFICACIONES.md`, commit + push (submódulos incluidos).

Hecho el 2026-11-23. Nota de despliegue: la imagen de la API copia `target/app.jar`, así
que antes de `docker compose up --build basketball-match-api` hay que empaquetar el jar
(`mvnw -DskipTests package`) en `C:\Develop\basketball\basketball-match-api`. La
publicación diaria (`resultados-ayer` → `basket curiosidades`) corre desde el checkout
principal cuando esta rama esté fusionada; hasta entonces, `basket curiosidades` a mano.
