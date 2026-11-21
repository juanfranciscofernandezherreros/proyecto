# Plan — Skill `curiosidades` (desde Postgres, en orden cronológico)

> **Fecha:** 2026-11-21 · **Relacionado:** [PLAN-curiosidades.md](PLAN-curiosidades.md) (pantalla
> `/curiosities`), [SDD.md](SDD.md), [VERIFICACION-SDD.md](VERIFICACION-SDD.md).
> **Repos:** raíz. **Estado:** en curso.

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

- [ ] Consulta `sql\consultas\2026-11-21_HHMM_curiosidades-cronologicas.sql` con cabecera.
- [ ] Ejecutarla sin filtro y con filtro de liga y fechas; comprobar el orden cronológico y
      contrastar algunas filas con las consultas de rankings del 2026-11-20.
- [ ] Skill `.claude/skills/curiosidades/SKILL.md` (cuándo usarla, comando, cómo contarlo).
- [ ] Evidencia en `VERIFICACION-SDD.md`, `basket verificar` en verde, commit + push.
