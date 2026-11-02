# Orquestador de CSV de baloncesto

## Configuración

Todas las rutas, el JDK, las URLs de los servicios y las credenciales están en
`config\basketball.env`, y la leen igual los `.bat`, los `.ps1` y los `.py`.

- Para cambiar algo **solo en esta máquina** (otra carpeta de datos, contraseñas
  reales…), crea `config\basketball.local.env` con las claves que quieras
  sobrescribir. Está fuera de git.
- Una variable de entorno con el mismo nombre tiene prioridad sobre ambos ficheros.
- Si `JAVA_HOME` está vacío o apunta a una carpeta que no existe, se usa el JDK 21
  más reciente instalado.

## Orquestador de competiciones

Este documento describe el orquestador `python\orchestrate_competition.py`.
Los scripts de uso diario están en `1_EJECUTAR\`; los que estos usan, en `scripts\`
(por función) y `python\`.
Su función es extraer todos los CSV de una competición de Flashscore, recuperar
automáticamente los que hayan quedado incompletos, validarlos y publicar un
resultado consolidado. No inicia launcher, batches ni escribe en una base de
datos.

## Qué hace

La ejecución sigue siempre esta secuencia:

1. Inicia `scripts\arranque\MANTENER_DESPIERTO.bat` para que el equipo no se suspenda.
2. Inicia `scripts\monitor\watch_csv_imports.bat`.
3. Muestra en la misma consola las líneas del watcher cuando se crea o cambia
   un CSV.
4. Extrae la competición en la ruta canónica.
5. Audita los CSV y recupera solo los partidos o datasets incompletos.
6. Repite la auditoría. Si queda algo pendiente, no consolida.
7. Publica los CSV finales consolidados.

Con `--retry-forever`, cualquier fallo temporal se reintenta tras 60 segundos
(o el valor indicado con `--retry-delay`) hasta que la auditoría quede sin
partidos pendientes.

## Rutas de datos

```text
C:\data\basketball\
  competitions\<country>\<competition>\   # CSV crudos y reanudables
  reports\<country>\<competition>\        # logs opcionales de ejecución

C:\data\basketball-ready\
  current\                                  # CSV finales consolidados
```

Los nombres de país y competición deben ser slugs en minúsculas, por ejemplo
`turkey` y `super-lig`.

## Ejecución persistente

Abre PowerShell en `C:\Develop\basketball` y ejecuta:

```powershell
py .\python\orchestrate_competition.py "https://www.flashscore.com/basketball/turkey/super-lig/" `
  --country turkey `
  --competition super-lig `
  --workers 2 `
  --resume `
  --retry-forever
```

La ventana debe permanecer abierta hasta que aparezca:

```text
CSV workflow complete: C:\data\basketball-ready\current
```

El watcher aparecerá intercalado con el resto del proceso:

```text
[watcher] [18:30:12]      1.234 bytes  C:\data\basketball\competitions\turkey\super-lig\...
```

## Reanudar una ejecución

Se puede cerrar el proceso y volver a ejecutar exactamente el mismo comando.
El orquestador detecta `run.json` y reanuda la carpeta de competición existente
en vez de comenzar de cero. Solo reintenta los CSV que la auditoría marque como
incompletos.

## Opciones útiles

| Opción | Uso |
| --- | --- |
| `--workers 1` | Modo más conservador si Flashscore bloquea o el equipo tiene pocos recursos. |
| `--workers 2` | Valor recomendado y predeterminado. |
| `--workers 3` | Máxima concurrencia permitida. |
| `--recover-attempts 5` | Número de intentos de recuperación por partido antes de esperar al siguiente ciclo. |
| `--retry-delay 120` | Espera 120 segundos entre ciclos persistentes. |
| `--no-monitors` | No inicia antibloqueo ni watcher; útil solo si ya están iniciados manualmente. |
| `--skip-extract` | Solo audita, recupera y consolida una carpeta ya extraída. |

## Diagnóstico

- Si no se ve actividad al inicio, Flashscore puede estar cargando el calendario
  o resolviendo la URL efectiva. El orquestador sigue activo mientras el
  proceso Python permanezca abierto.
- Si hay un fallo transitorio, con `--retry-forever` se verá el mensaje de
  reintento y el proceso continuará automáticamente.
- Los CSV crudos nunca se borran al consolidar. Eso permite reanudar o revisar
  cualquier partido sin volver a extraer toda la competición.

## Auditoría automática

Al terminar correctamente, el orquestador guarda un informe
`csv-audit-<fecha>.json` en:

```text
C:\data\basketball\reports\<country>\<competition>\
```

El informe no importa ni modifica la base de datos. Compara el `manifest.json` que estaba
en `basketball-ready\current` antes de la publicación con el nuevo manifiesto,
incluye las filas por flujo CSV, su diferencia, el inventario final y los
estados por partido. También toma, en modo solo lectura, los conteos antes y
después de las seis tablas PostgreSQL del proyecto. La condición de éxito es
`pending_matches: 0` y `status: complete`.

La opción `--no-db-audit` permite omitir estas consultas de lectura si
PostgreSQL no está disponible. Esta auditoría no importa ni modifica datos de
la base de datos.
