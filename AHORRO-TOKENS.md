# Ahorro de tokens

Registro de cada optimización del consumo de tokens de Claude en este proyecto, con
cifras medidas. Se mide con:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd tokens"
```

**Tokens ≈ caracteres / 4.** Dos tipos de carga:

- **Fija:** se paga en **cada mensaje** de cada sesión: `CLAUDE.md`, las reglas de
  `.claude\rules\` sin `paths:` y la descripción de cada skill que Claude puede invocar.
- **Al usar una skill:** su `SKILL.md` entero, solo cuando se invoca.

Lo que más gasta, con diferencia, es el historial de una sesión larga (se reenvía en
cada mensaje). Ninguna cifra de aquí lo incluye: abrir sesión nueva o `/clear` al
cambiar de tarea es el ahorro más grande y no cuesta nada.

## Estado actual (2026-11-17, `basket tokens`)

| Carga fija | Caracteres | ~Tokens |
|---|---:|---:|
| `CLAUDE.md` | 569 | 142 |
| Reglas sin `paths:` (`consultas-sql`, `flujo-de-trabajo`, `idioma-espanol`) | 1.558 | 389 |
| Descripciones de 16 skills | 2.267 | 567 |
| **Total por mensaje** | **4.394** | **~1.100** |

Reglas **condicionales** (llevan `paths:` y solo se cargan al tocar sus ficheros):
`microservicios-spring` (2.667 car, ~670 tok; `*.java`, `pom.xml`) y `score-summary`
(1.124 car, ~280 tok; scraper, match-summary, projector).

## Registro de mejoras

Las cifras "antes" de las filas 1–4 se midieron con `wc -c` (bytes; las tildes cuentan
doble) porque `basket tokens` aún no existía. Desde la fila 5, todo sale de `basket tokens`.

| # | Fecha | Mejora | Antes → después | Ahorro | Commit |
|---|---|---|---|---|---|
| 1 | 2026-11-17 | Aviso por Telegram de cada CSV y de la predicción: el estado se ve en el móvil sin preguntar a Claude | Preguntar a Claude → 0 tokens | Una consulta entera cada vez | `17245de`, `c540231` |
| 2 | 2026-11-17 | `CLAUDE.md` mínimo (la tabla de skills y reglas sobraba: se cargan solas) | 2.626 → 510 bytes | ~530 tok **por mensaje** | `fae464f` |
| 3 | 2026-11-17 | `resultados-ayer`: línea `RESUMEN:` al bot (con la tarea al iniciar sesión, 0 tokens al día); skill fina con Haiku que lee solo `RESUMEN:` | Descripción 704 → 148 · fichero 4.721 → 1.549 bytes · modelo de la sesión → Haiku | ~140 tok por mensaje · ~800 tok por uso, más no leer el log | `d6b0e22` |
| 4 | 2026-11-17 | Descripciones de 14 skills a ~140 caracteres; Haiku en `aviso-telegram` y `cuadrar-partidos-dia` | 6.230 → 2.177 bytes | ~1.000 tok **por mensaje** | `fbd9441` |
| 5 | 2026-11-17 | `procesar-pendientes`: línea `RESUMEN:` al bot y skill fina que lee solo `RESUMEN:` | Fichero 5.596 bytes → 1.875 car · descripción 708 bytes → 167 car | ~930 tok por uso, ~130 por mensaje | `84a641c` |
| 6 | 2026-11-17 | Reglas `backlog-de-pasos` y `flujo-bug-plan-sdd-commit-por-paso` juntas en `flujo-de-trabajo` (decían lo mismo) | 2.494 → 716 car · total fijo 6.172 → 4.394 car | ~445 tok **por mensaje** | `COMMIT6` |

**Acumulado en carga fija:** unos 2.250 tokens menos en cada mensaje de cada sesión.

> **Corrección (2026-11-17):** la primera versión de `basket tokens` contaba como fijas las
> reglas con `paths:` (`microservicios-spring`, `score-summary`), que ya eran
> condicionales. El total fijo real entonces era ~1.540 tokens, no ~2.490. No es un ahorro nuevo:
> era un error de medida.

## Próximas mejoras

| Mejora | Ahorro estimado |
|---|---|
| Skills largas finas (`diagnosticar-partido` 6.007, `auditar-datos` 4.801, `aviso-telegram` 4.370 car), como `resultados-ayer` | ~700–1.000 tok por uso cada una |
| Haiku en `diagnosticar-partido`, `auditar-datos` y `commit-multirepo` (hoy Sonnet) | Mismos tokens, mucho más baratos |

## Norma

Tras cada optimización: `basket tokens` antes y después, una fila en el registro y el
estado actual al día.
