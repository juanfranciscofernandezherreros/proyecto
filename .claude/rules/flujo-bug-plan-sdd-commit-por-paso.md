# Flujo de cada bug o tarea: plan + SDD + commit por paso

Para cada bug o tarea nueva en el proyecto Basketball:

1. **Primero un plan detallado** de la tarea (fichero de plan por áreas, estilo
   `docs/PLAN-*.md`), antes de tocar código.
2. **Hacer que cumpla todo el SDD** (áreas y requisitos de `docs/SDD.md`) y dejar
   evidencia en `docs/VERIFICACION-SDD.md`.
3. **Un commit + push por cada paso** de la tarea (no acumular todo en un commit
   final).

**Por qué:** un plan detallado y alineado con el SDD deja cada paso tan especificado
que puede ejecutarlo un modelo más barato; y commitear/pushear paso a paso da puntos
de control y trazabilidad.

**Cómo aplicarlo:** al empezar un bug o tarea, escribir el plan primero; implementar
por pasos; tras cada paso verificado (gate `Verificar.ps1`), commit + push en el repo
correspondiente (multi-repo + submódulos en `proyecto`). El push es una acción
explícita: el usuario ya ha pedido commit + push por paso para este flujo, no para
otros trabajos. Relacionado con la skill `normas-basketball` y la regla
`idioma-espanol.md`.
