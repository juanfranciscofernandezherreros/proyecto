# Proyecto Basketball

Flujo: Flashscore → CSV → launcher (8088) → **Postgres** (55432) → projector →
**MongoDB** (27017) → API (8082) → web (8083). Explicado en `index.html`.

- Todo se lanza con `1_EJECUTAR\basket.cmd <comando>` (`basket ayuda`). Nunca
  `mvn spring-boot:run` ni `npm run dev` (puertos equivocados).
- `basket verificar` es el gate: debe dar VERDE.
- Toda consulta SQL ejecutada se guarda en `sql\consultas\`.
- Diseño y operación: `docs\SDD.md`, `docs\ESPECIFICACIONES.md`.
- Tras optimizar tokens: `basket tokens` y una fila en `AHORRO-TOKENS.md`.
