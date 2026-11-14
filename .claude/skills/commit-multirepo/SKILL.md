---
name: commit-multirepo
description: Hace commit y push en el proyecto Basketball respetando su estructura de varios repositorios — commit en el submódulo que cambió, verificación previa, push, actualización del puntero en el repositorio padre y registro de la evidencia en docs\VERIFICACION-SDD.md. Usar cuando el usuario pida commitear, hacer push, subir los cambios, o cerrar un paso de una tarea, y siempre que haya cambios dentro de un submódulo.
---

# Commit y push en un proyecto de varios repositorios

`C:\Develop\basketball` es el repositorio padre (`proyecto`). Cada subproyecto es
un repositorio propio, enlazado como submódulo:

| Carpeta | Tipo | Rama | Comprobación antes de subir |
|---|---|---|---|
| `basketball-match-api` | Java / Maven | `main` | `./mvnw verify` |
| `basketball-match-projector` | Java / Maven | `main` | `mvn verify` |
| `csv-extra-batch` | Java / Maven | `main` | `mvn verify` |
| `basketball-match-web` | Node / Vite | `main` | `npm run build` y `npm test` |
| `python-pyppeter` | Python | `KAN-341/readme-extraccion-csv` | `python -m unittest` |
| `local-validation` | docker compose | `main` | — |
| raíz (`scripts`, `docs`, `sql`, `1_EJECUTAR`, `.claude`) | padre | `main` | `1_EJECUTAR\VERIFICAR.bat` si toca operación |

`python-pyppeter` no está en `main`: confirmar la rama con
`git -C python-pyppeter rev-parse --abbrev-ref HEAD` antes de subir, y no cambiarla.

## Cuándo se hace

Solo cuando el usuario lo pide. La excepción es el flujo de bugs (regla
`flujo-bug-plan-sdd-commit-por-paso`): ahí ya está pedido un commit y un push por
cada paso verificado.

## 1. Ver qué ha cambiado y dónde

```bash
cd "C:/Develop/basketball" && git status --short && git submodule foreach --quiet 'n=$(git status --short | wc -l); [ "$n" -gt 0 ] && echo "$name: $n cambios" || true'
```

En el padre, una línea ` M <submodulo>` significa que el submódulo tiene commits
nuevos o cambios sin commitear; no es un fichero que se pueda añadir tal cual.

## 2. Para cada submódulo con cambios

Dentro de la carpeta del submódulo:

1. **Verificar** con el comando de la tabla. Si falla, no se commitea: se arregla
   o se le cuenta al usuario con la salida.
2. **Commit** solo de lo relacionado con la tarea. Mensaje en español, en
   imperativo o nominal, como los del historial ("Normalizar competiciones al
   cargar fixtures").
3. **Push** a la rama en la que está el submódulo.

Los hooks `pre-push` de cada subrepo (`.githooks/pre-push`) compilan antes de
subir, pero solo actúan si se activaron con
`git config core.hooksPath .githooks`. En esta máquina no están activados en
ningún submódulo, así que la verificación del punto 1 no es opcional.

## 3. Actualizar el puntero en el padre

Después de subir el submódulo, nunca antes: un puntero a un commit que no está en
el remoto rompe el clonado a los demás.

```bash
cd "C:/Develop/basketball" && git add <submodulo> && git status --short
```

El commit del padre incluye el puntero y lo que acompañe a la tarea en la raíz
(`docs`, `scripts`, `sql\consultas`). El historial usa mensajes como
"Verificacion M4 (python-pyppeter en verde) y puntero de submodulo".

## 4. Registrar la evidencia

Si el cambio corresponde a un requisito del SDD, añadirlo a
`docs\VERIFICACION-SDD.md` antes del commit del padre:

- Una fila en la tabla del resumen (§1): identificador (`D<n>` para desarrollo,
  `M<n>` para mantenimiento), cambio, área del SDD y estado.
- Su bloque en la matriz de trazabilidad (§2), con las columnas
  `Requisito | Cambio | Fichero / commit | Verificación | OK`, citando el hash
  corto del commit del submódulo y la comprobación concreta que se hizo.

No marcar como verificado algo que no se ha comprobado.

## 5. Push del padre y comprobación final

```bash
cd "C:/Develop/basketball" && git push origin main && git status -sb | head -1 && git submodule status
```

Correcto cuando `main` no va por delante de `origin/main` y ninguna línea de
`git submodule status` empieza por `+` (puntero desalineado) ni por `-`
(submódulo sin inicializar).

## Normas

- No usar `git add -A` en el padre a ciegas: revisar antes el `git status`.
- No commitear `config\basketball.local.env`, `.claude\settings.local.json`,
  `logs\`, `outputs\` ni datos de `C:\data`.
- No saltarse hooks (`--no-verify`) ni forzar el push.
- No cambiar de rama ni rebasar un submódulo sin que el usuario lo pida.
- Si hay cambios ajenos a la tarea, dejarlos fuera del commit y avisar.
