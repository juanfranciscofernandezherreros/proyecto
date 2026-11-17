# -*- coding: utf-8 -*-
r"""Lanzador: mide lo que gasta Claude en tokens con este proyecto (basket tokens).

- Carga fija (en CADA sesion): CLAUDE.md, .claude\rules\*.md y la descripcion de cada
  skill que Claude puede invocar (las que tienen disable-model-invocation no cuentan).
- Carga al usar una skill: su SKILL.md entero.

Tokens aproximados = caracteres / 4. Sirve para rellenar AHORRO-TOKENS.md con cifras
medidas antes y despues de cada optimizacion.
Uso: basket tokens"""
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[3]


def tokens(caracteres):
    return round(caracteres / 4)


def _frontmatter(texto):
    m = re.match(r"^---\n(.*?)\n---", texto.replace("\r\n", "\n"), re.S)
    return m.group(1) if m else ""


def medir(raiz=RAIZ):
    """Devuelve {fijo: [(nombre, caracteres)], skills: [(nombre, desc, fichero, modelo)],
    total_fijo}. Solo cuenta las skills que Claude puede invocar."""
    fijo, condicional = [], []
    claude = raiz / "CLAUDE.md"
    if claude.exists():
        fijo.append(("CLAUDE.md", len(claude.read_text(encoding="utf-8"))))
    for r in sorted((raiz / ".claude" / "rules").glob("*.md")):
        texto = r.read_text(encoding="utf-8")
        # Con paths: solo se carga al tocar esos ficheros: no es carga fija.
        destino = condicional if re.search(r"^paths:", _frontmatter(texto), re.M) else fijo
        destino.append((f"rules/{r.name}", len(texto)))
    skills = []
    for f in sorted((raiz / ".claude" / "skills").glob("*/SKILL.md")):
        texto = f.read_text(encoding="utf-8")
        fm = _frontmatter(texto)
        if re.search(r"^disable-model-invocation:\s*true", fm, re.M):
            continue
        desc = re.search(r"^description:\s*(.*)$", fm, re.M)
        modelo = re.search(r"^model:\s*(\S+)", fm, re.M)
        skills.append((f.parent.name, len(desc.group(1)) if desc else 0, len(texto),
                       modelo.group(1) if modelo else "-"))
    total = sum(c for _, c in fijo) + sum(d for _, d, _, _ in skills)
    return {"fijo": fijo, "condicional": condicional, "skills": skills, "total_fijo": total}


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    m = medir()
    print("== Carga fija (en cada sesión) ==")
    for nombre, c in m["fijo"]:
        print(f"  {nombre:<44} {c:>6} car  ~{tokens(c):>5} tok")
    desc = sum(d for _, d, _, _ in m["skills"])
    print(f"  {'descripciones de ' + str(len(m['skills'])) + ' skills':<44} {desc:>6} car  ~{tokens(desc):>5} tok")
    print(f"  {'TOTAL FIJO':<44} {m['total_fijo']:>6} car  ~{tokens(m['total_fijo']):>5} tok")
    print("\n== Reglas condicionales (solo al tocar sus ficheros, paths:) ==")
    for nombre, c in m["condicional"]:
        print(f"  {nombre:<44} {c:>6} car  ~{tokens(c):>5} tok")
    print("\n== Al usar cada skill ==")
    print(f"  {'skill':<28} {'desc':>5} {'fichero':>8} {'~tok':>6}  modelo")
    for nombre, d, f, modelo in sorted(m["skills"], key=lambda s: -s[2]):
        print(f"  {nombre:<28} {d:>5} {f:>8} {tokens(f):>6}  {modelo}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
