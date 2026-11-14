# Instrucciones del proyecto Basketball

Flujo de datos: CSV → `csv-batch-launcher` → **Postgres** → `basketball-match-projector`
→ **MongoDB** → `basketball-match-api` → **web**.

- Web http://localhost:8083 · API http://localhost:8082 · Launcher http://localhost:8088
  · Mongo 27017 · Postgres 55432
- Nunca lanzar piezas sueltas con `mvn spring-boot:run` ni `npm run dev` (puertos
  equivocados: 8080 y 5173).
- Toda consulta SQL ejecutada contra la base de datos se guarda en `sql\consultas\`.

El detalle vive fuera de este fichero:

| Qué | Dónde |
|---|---|
| Arrancar la web y el procesamiento de CSV | skill `arrancar-todo` |
| Extraer resultados de la Euroliga hasta Postgres | skill `extraer-euroliga` |
| Normas de desarrollo y flujo SDD → plan → verificación | skill `normas-basketball` |
| Formato de los ficheros de `sql\consultas\` | `.claude\rules\consultas-sql.md` |
| SCORE_SUMMARY con identidad de partido | `.claude\rules\score-summary.md` |
| Idioma, flujo de bugs y microservicios Spring | `.claude\rules\` |
| Skills, agente y comando de CRUD/microservicios | `.claude\skills\`, `.claude\agents\`, `.claude\commands\` |
| Arquitectura y operación | `docs\SDD.md`, `docs\ESPECIFICACIONES.md` |
