---
name: csv-faltan
description: Lista los partidos a los que les faltan CSV por generar y por qué no se generaron (basket csv-faltan, solo lectura). Usar cuando pregunten qué CSV faltan o por qué un partido sale sin datos aunque se procesó.
model: haiku
---

# CSV que faltan por generar

Sin preguntar. Solo lectura (refresca la auditoría de fixtures). Con salida a un
fichero del directorio temporal de la sesión:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd csv-faltan [match_id]" > <fichero> 2>&1
```

Una URL `http://localhost:8083/matches/<match_id>` → pasar ese `match_id`.

Leer las líneas del partido (`sin CSV`, `CSV sin cargar`, `motivo`) y la `RESUMEN:`.
El informe completo queda en `REPORT_DIR\CSV_FALTAN_<stamp>.csv`.

| Motivo | Qué significa / qué hacer |
|---|---|
| `ERROR: …ERR_NAME_NOT_RESOLVED` / sin red | Falló la extracción por red; el «Proceso terminado» del log no implica éxito. Relanzar `basket pendientes` con red |
| `ERROR:` otro | Ver el log `PROCESAR_MATCHIDS_<run>_<match_id>.log`; reintentar con `basket reextraer <match_id>` |
| `COMPLETED pero sigue pendiente` | Flashscore no publica la sección o no se cargó: `CSV sin cargar` ≠ `-` → `basket procesar-csv` |
| `nunca se ha intentado` | `basket pendientes` |
| «no lo marca como pendiente» | No le falta ningún CSV; si la web no lo muestra, skill `diagnosticar-partido` |
