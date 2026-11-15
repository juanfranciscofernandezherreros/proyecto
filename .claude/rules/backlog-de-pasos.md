# Backlog de pasos antes de desarrollar

Siempre que se vaya a desarrollar algo (código, scripts, skills, consultas de
escritura, cambios de configuración), **antes de tocar nada** se escribe un backlog
con los pasos que se van a dar, y se va marcando según se completan.

- El backlog va en el plan de la tarea (`docs/PLAN-*.md`), en una sección
  `## Backlog`, como lista de casillas: `- [ ]` pendiente, `- [x]` hecho.
- Cada paso es una acción concreta y comprobable (qué fichero o qué resultado).
- Se marca `[x]` **en el momento** en que el paso queda hecho y verificado, no todos
  al final. Si un paso falla o se descarta, se deja sin marcar y se anota por qué.
- Si el plan cambia a mitad, se actualiza el backlog (pasos nuevos o tachados) en
  vez de seguir con uno que ya no es verdad.
- El mismo backlog se refleja en la lista de tareas de la sesión, para que se vea
  el avance sin abrir el fichero.
- Al terminar, el backlog debe decir la verdad: lo que quedó sin hacer sigue en `[ ]`.

No hace falta para preguntas, análisis de solo lectura o cambios de una línea.

**Por qué:** el 2026-11-15 el usuario pidió poder saber en todo momento qué se está
haciendo y qué falta, y verlo marcado paso a paso.

**Cómo aplicarlo:** es el primer paso del flujo de
`flujo-bug-plan-sdd-commit-por-paso.md`: plan con backlog → implementar paso a paso
marcando → verificación → commit + push por paso.
