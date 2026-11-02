# Recuperación de CSV de Euroliga

Desde esta carpeta, con Python y Docker disponibles:

```powershell
py complete_euroleague_csv.py
py complete_euroleague_csv.py --execute
```

El primer comando consulta PostgreSQL y muestra el plan. El segundo ejecuta
secuencialmente los datasets pendientes con el scraper oficial. No ejecuta batch,
no borra información y no escribe en PostgreSQL.

La selección predeterminada son los diez partidos del 15–16 de octubre de 2026,
no una detección automática de la jornada vigente. Para otra selección:

```powershell
py complete_euroleague_csv.py --run-dir C:\data\basketball\runs-20261018\euroleague --match j7sNJUeJ --execute
```

Repetir `--match` por cada ID, conservando sus mayúsculas. Los IDs deben existir
en el inventario de la ejecución indicada. El script consulta exclusivamente
`basketball` con usuario `test` dentro del contenedor `local-validation-postgres-1`
(equivalente a la conexión del host localhost:55432). Se puede cambiar el nombre
del contenedor con `--container`.

Comprueba manifiestos e integridad básica (existencia y número de filas) de los
CSV locales. Distingue datos extraídos de datos persistidos; la mera existencia
de una fila en PostgreSQL no certifica una importación completa. No reintenta
datasets declarados `not_available` por el scraper. Para tablas con importaciones
parciales o varias filas por entidad, el recuento es orientativo, no una auditoría
de igualdad del contenido.

El manifiesto de cada partido prevalece sobre el inventario de competición tras
recuperar un bundle. Los CSV recuperados quedan en la carpeta de ese partido.
Un bloqueo evita ejecutar dos instancias simultáneas de este script; si se mata
el proceso abruptamente, comprobar que no sigue activo antes de eliminar
`.complete-euroleague.lock` en la carpeta de la ejecución.
