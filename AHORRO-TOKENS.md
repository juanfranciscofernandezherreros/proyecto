# Ahorro de tokens

Registro de cada optimización del consumo de tokens de Claude en este proyecto, con
cifras medidas. Se mide con:

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd tokens"
```

**Tokens ≈ caracteres / 4.** Dos tipos de carga:

- **Fija:** se paga en **cada mensaje** de cada sesión: `CLAUDE.md`, `.claude\rules\*.md`
  y la descripción de cada skill que Claude puede invocar.
- **Al usar una skill:** su `SKILL.md` entero, solo cuando se invoca.

Lo que más gasta, con diferencia, es el historial de una sesión larga (se reenvía en
cada mensaje). Ninguna cifra de aquí lo incluye: abrir sesión nueva o `/clear` al
cambiar de tarea es el ahorro más grande y no cuesta nada.

## Estado actual (2026-11-17, `basket tokens`)

| Carga fija | Caracteres | ~Tokens |
|---|---:|---:|
| `CLAUDE.md` | 569 | 142 |
| Reglas (`.claude\rules\`, 6 ficheros) | 7.127 | 1.781 |
| Descripciones de 16 skills | 2.267 | 567 |
| **Total por mensaje** | **9.963** | **~2.490** |

## Registro de mejoras

Las cifras "antes" de las filas 1–4 se midieron con `wc -c` (bytes; las tildes cuentan
doble) porque `basket tokens` aún no existía. Desde la fila 5, todo sale de `basket tokens`.

| # | Fecha | Mejora | Antes → después | Ahorro | Commit |
|---|---|---|---|---|---|
| 1 | 2026-11-17 | Aviso por Telegram de cada CSV y de la predicción: el estado se ve en el móvil sin preguntar a Claude | Preguntar a Claude → 0 tokens | Una consulta entera cada vez | `17245de`, `c540231` |
| 2 | 2026-11-17 | `CLAUDE.md` mínimo (la tabla de skills y reglas sobraba: se cargan solas) | 2.626 → 510 bytes | ~530 tok **por mensaje** | `fae464f` |
| 3 | 2026-11-17 | `resultados-ayer`: línea `RESUMEN:` al bot (con la tarea al iniciar sesión, 0 tokens al día); skill fina con Haiku que lee solo `RESUMEN:` | Descripción 704 → 148 · fichero 4.721 → 1.549 bytes · modelo de la sesión → Haiku | ~140 tok por mensaje · ~800 tok por uso, más no leer el log | `d6b0e22` |
| 4 | 2026-11-17 | Descripciones de 14 skills a ~140 caracteres; Haiku en `aviso-telegram` y `cuadrar-partidos-dia` | 6.230 → 2.177 bytes | ~1.000 tok **por mensaje** | `fbd9441` |
| 5 | 2026-11-17 | `procesar-pendientes`: línea `RESUMEN:` al bot y skill fina que lee solo `RESUMEN:` | Fichero 5.596 bytes → 1.875 car · descripción 708 bytes → 167 car | ~930 tok por uso, ~130 por mensaje | pendiente de subir (prueba real en curso) |

**Acumulado en carga fija:** unos 1.700 tokens menos en cada mensaje de cada sesión.

## Próximas mejoras

| Mejora | Ahorro estimado |
|---|---|
| Regla `microservicios-spring` solo al tocar Java (`paths:` en su frontmatter) | ~670 tok por mensaje cuando no se toca Java |
| Reglas `score-summary` y `flujo-bug-plan-sdd-commit-por-paso` solo al desarrollar (`paths:`) | ~550 tok por mensaje |
| Skills largas finas (`diagnosticar-partido` 6.007, `auditar-datos` 4.801, `aviso-telegram` 4.370 car), como `resultados-ayer` | ~700–1.000 tok por uso cada una |
| Haiku en `diagnosticar-partido`, `auditar-datos` y `commit-multirepo` (hoy Sonnet) | Mismo número de tokens, mucho más baratos |

## Norma

Tras cada optimización: `basket tokens` antes y después, una fila en el registro y el
estado actual al día.
