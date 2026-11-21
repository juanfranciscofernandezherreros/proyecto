# Plan — Skill `curiosidades` (desde Postgres, en orden cronológico)

> **Fecha:** 2026-11-21 · **Relacionado:** [PLAN-curiosidades.md](PLAN-curiosidades.md) (pantalla
> `/curiosities`), [SDD.md](SDD.md), [VERIFICACION-SDD.md](VERIFICACION-SDD.md).
> **Repos:** raíz y `basketball-match-web`. **Estado:** en curso (pestaña «Periódico»).

## 1. Qué se quiere

Una skill que cuente curiosidades sacadas directamente de nuestras tablas de Postgres
(`results.results`, `point_by_point.point_by_point_event`, `stats_player.stats_player`),
**ordenadas cronológicamente** (del partido más antiguo al más reciente, fecha de Madrid).

## 2. Decisiones

- **Una sola consulta** de lectura que devuelve una fila por curiosidad con fecha:
  `fecha`, `liga`, `partido`, `final`, `tipo`, `detalle`, `match_id`, ordenada por
  `event_datetime` y, dentro del partido, por tipo. Así la skill hace una única llamada.
- **Mismas reglas que las consultas de curiosidades del 2026-11-20** (puntos de cada canasta
  por diferencia de marcador, rachas «limpias», jugador = nombre + equipo, nulos = 0).
- **Umbrales** para que solo salga lo llamativo: remontada ≥ 15, racha ≥ 15-0, paliza ≥ 35,
  ≥ 15 cambios de líder, partido ganado con la última canasta, triple-doble, 40+ puntos,
  cuarto récord de su competición y partido con más/menos puntos de su competición.
- **Filtros opcionales** con variables de psql (`-v desde=AAAA-MM-DD -v hasta=… -v liga=…`):
  sin ellas el fichero se ejecuta tal cual sobre todo.
- Las curiosidades sin fecha (medias de temporada, prórrogas por liga) quedan fuera: ya están
  en las consultas de rankings y en la pantalla.
- Sin comando `basket` nuevo: la skill es una llamada `docker exec … psql`, como
  `ultimos-resultados`, y es autocontenida.

## Backlog

- [x] Consulta `sql\consultas\2026-11-21_1000_curiosidades-cronologicas.sql` con cabecera.
- [x] Ejecutarla sin filtro y con filtro de liga y fechas; comprobar el orden cronológico y
      contrastar algunas filas con las consultas de rankings del 2026-11-20 (447 filas;
      remontadas 61, prórrogas 54, triples-dobles 13 y 40+ 30, iguales que las de referencia).
- [x] Skill `.claude/skills/curiosidades/SKILL.md` (cuándo usarla, comando, cómo contarlo).
- [x] Evidencia en `VERIFICACION-SDD.md`, `basket verificar` en verde, commit + push.

## 3. Segunda petición (2026-11-21): la web lo redacta como un periódico, en orden cronológico

Pestaña **«Periódico»** en `/curiosities` (web, sobre los mismos datos de la API que el guion
de vídeo: `/api/v1/curiosities` y `/api/v1/comebacks`):

- Una **edición por día** (fecha de Madrid), del día más antiguo al más reciente, con un
  titular de portada (la curiosidad de más peso del día) y una entradilla.
- Dentro del día, una **noticia por partido en orden de hora de inicio**: titular, subtítulo
  (partido, marcador, competición y hora) y crónica (frase de arranque + curiosidades).
- Titular por peso: récord de temporada > 40 puntos > remontada > última canasta >
  triple-doble > racha > paliza > igualdad > cuartos > totales > de principio a fin.
- Botón «Copiar periódico» (texto plano). Lo que no tiene fecha (temporada) no entra.

### Backlog (periódico)

- [ ] `utils/newspaper.ts` (reutiliza la recogida de frases de `videoScript.ts`) con tests.
- [ ] Pestaña «Periódico» con estilo de periódico; `typecheck` y tests en verde.
- [ ] Revisar en el navegador con datos reales (orden cronológico de días y de partidos).
- [ ] Evidencia, `basket verificar` en verde, commit + push y llevarlo a `main`.
