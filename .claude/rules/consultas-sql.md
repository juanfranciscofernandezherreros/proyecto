# Consultas a la base de datos

Toda consulta SQL que se ejecute contra la base de datos del proyecto (PostgreSQL de
`local-validation`, por `docker exec ... psql`, el datasource de Grafana o cualquier otra
vía) se guarda en `sql\consultas\` para poder repetirla más adelante.

- **Un fichero por consulta** (o por grupo de consultas de una misma tarea), con nombre
  `AAAA-MM-DD_HHMM_<tema-en-minusculas>.sql`, por ejemplo
  `2026-11-03_0925_partidos-sin-event-time.sql`.
- **Cada fichero es una guía autoexplicativa**: alguien que no conozca el problema debe
  poder entender, solo leyéndolo, para qué sirve, cuándo usarlo y qué hacer con el
  resultado. Cabecera obligatoria en comentarios SQL:
  ```sql
  -- =============================================================================
  -- TÍTULO CORTO
  -- =============================================================================
  -- Fecha:     2026-11-03 09:25
  -- Tipo:      LECTURA | ESCRITURA
  -- Ejecutar:  docker exec -i local-validation-postgres-1 psql -U test -d basketball < sql\consultas\<fichero>
  --
  -- PARA QUÉ SIRVE   el problema o la pregunta, con contexto (tablas, columnas, por qué importa)
  -- CUÁNDO USARLA    en qué situación conviene volver a ejecutarla
  -- CÓMO LEER EL RESULTADO  qué significa cada columna y qué valores son buenos o malos
  -- QUÉ HACER DESPUÉS       siguiente paso según el resultado (otra consulta, un script...)
  -- RESULTADO EL <fecha>    lo que devolvió o cuántas filas cambió cuando se ejecutó
  ```
- **Cada consulta dentro del fichero va precedida de un comentario** con el número de
  paso, qué hace y por qué (`-- PASO 1 · ...`). En las de escritura, además: qué filas
  toca, qué condiciones protegen los datos existentes y cómo comprobar el efecto.
- **El SQL exacto que se ejecutó**, listo para volver a lanzarlo tal cual (sin variables
  de shell ni escapes de la línea de comandos).
- **Las de escritura** (`INSERT`, `UPDATE`, `DELETE`, DDL) se marcan como `ESCRITURA`, se
  guardan **antes** de ejecutarlas y llevan, si existe, la consulta de lectura que permite
  comprobar el resultado.
- Las consultas que solo sirven de paso intermedio (por ejemplo, ver la estructura de una
  tabla) pueden agruparse en el fichero de la tarea a la que pertenecen.
