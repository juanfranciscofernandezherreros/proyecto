---
name: estado-del-sistema
description: Vistazo de solo lectura al estado del proyecto Basketball (servicios levantados, últimas cargas, último resultado por liga, partidos pendientes). Usar cuando el usuario pregunte cómo está todo, si funciona, qué está arrancado o qué falta por procesar.
---

# Estado del sistema

Una sola llamada, de solo lectura:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\ESTADO.bat"
```

Imprime unas 30 líneas y termina con `RESUMEN`, que lista lo que falla. Código de
salida 0 = todo responde, 1 = falta algo. No lanzar comandos sueltos (`docker ps`,
`curl`, consultas) para lo que ya da el script.

## Cómo leerlo

- **CONTENEDORES**: `PARADO` en mongo, projector, api o web → skill `arrancar-todo`.
- **SERVICIOS**: código HTTP; `0` = no escucha nadie. El launcher devuelve `404`
  en esa ruta estando levantado: solo es fallo si da `0`.
- **CARGAS**: buenas son `COMPLETED` con `exit=0`. Si la más reciente es de hace
  días, no se está procesando nada.
- **RESULTADOS POR LIGA**: la última columna son partidos jugados sin resultado;
  mayor que cero → skill `extraer-resultados`.
- **PENDIENTES**: partidos a los que falta algún dataset → skill
  `procesar-pendientes`.

Solo si web, API, Postgres y Mongo están levantados, se puede añadir la
verificación del SDD: `cmd //c "C:\Develop\basketball\1_EJECUTAR\VERIFICAR.bat"`.

## Cómo contarlo

Corto y empezando por lo que no funciona, con la skill que lo arregla. No arrancar
ni corregir nada por iniciativa propia: solo informar.
