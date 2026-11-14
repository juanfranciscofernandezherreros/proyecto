# SCORE_SUMMARY trae identidad de partido (igual que RESULTS)

`SCORE_SUMMARY_*.csv` incluye, además de marcador/parciales, los campos
`eventTime, eventDatetime, homeTeam, awayTeam, homeScore, awayScore, country,
competition` (contrato en `python-pyppeter/csv_contracts.py`).

- La hora sale de `.duelParticipant__startTime` de la ficha del partido;
  país/competición, de la ruta `.../competitions/<pais>/<comp>/`.
- El JAR `csv-extra-batch/match-summary` los carga en `results.results`
  (`event_time` / `event_datetime` / `country` / `competition`), de modo que un
  partido que llega solo por SCORE_SUMMARY ya no queda sin hora ni país y **sí
  aparece en la web** (la API filtra `finished` por `result.eventTime`).
- Los SCORE_SUMMARY antiguos de 15 columnas se siguen aceptando.
- Si el scrape de la hora falla, queda el backfill desde `fixtures` en
  `sql\consultas\`.

Detalle completo en `docs\ESPECIFICACIONES.md` (sección 11).
