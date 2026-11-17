# -*- coding: utf-8 -*-
r"""Lanzador: previa y pronosticos de la proxima jornada (skill pronostico-jornada).

Uso:
  pronostico.py datos [pais] [competicion] [fichero]   por defecto europe euroleague
      Calcula el pronostico de la proxima jornada y escribe el borrador JSON (sin textos).
  pronostico.py publicar <fichero>
      Valida el borrador ya redactado y lo publica en MongoDB (prediction_articles).

Codigo de salida: 0 = hecho; 1 = no se pudo (sin calendario, borrador incompleto, error)."""
import json
import sys
from pathlib import Path

from _base import CFG, SCRIPTS_PY, ensure

sys.path.insert(0, str(SCRIPTS_PY / "pronostico"))
import previa

try:  # los nombres de equipo pueden traer caracteres fuera de cp1252
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

WEB = "http://localhost:8083/predictions/"


def _datos(args):
    pais = args[0] if len(args) > 0 else "europe"
    competicion = args[1] if len(args) > 1 else "euroleague"
    if ensure("postgres"):
        return 1
    try:
        borrador = previa.construir_borrador(previa.leer_datos(CFG, pais, competicion), pais, competicion)
        previa.ampliar(borrador, previa.leer_partidos(CFG, pais, competicion))
    except (ValueError, RuntimeError) as error:
        print(f"[ERROR] {error}")
        return 1
    if len(args) > 2:
        destino = Path(args[2])
    else:
        destino = Path(CFG.get("REPORTS_DIR", r"C:\data\basketball\reports")) / "pronosticos" / f"{borrador['_id']}.json"
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text(json.dumps(borrador, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{borrador['title']} · {len(borrador['games'])} partidos · {borrador['localMatches']} resultados usados")
    for partido in borrador["games"]:
        print(f"  {partido['startsAt']}  {partido['homeTeam']} - {partido['awayTeam']}  ->  "
              f"{partido['winner']} {partido['winnerProbability']}%")
    contraste = borrador["_ayuda"].get("contraste") or {}
    if contraste.get("partidos"):
        print(f"Contraste del modelo: {contraste['aciertos']} de {contraste['partidos']} ganadores acertados "
              f"({contraste['porcentaje']}%); siempre local: {contraste['porcentaje_siempre_local']}%; "
              f"error medio del margen: {contraste['error_medio_margen']} puntos")
    discrepan = [p for p in borrador["games"]
                 if p["_ayuda"].get("margenPistaLocal") is not None
                 and (p["_ayuda"]["margenPistaLocal"] >= 0) != (p["_ayuda"]["margenLocal"] >= 0)]
    for partido in discrepan:
        print(f"  OJO: el modelo de pista discrepa en {partido['homeTeam']} - {partido['awayTeam']} "
              f"(margen local {partido['_ayuda']['margenPistaLocal']} frente a {partido['_ayuda']['margenLocal']})")
    print(f"Borrador: {destino}")
    print("Falta redactar `introduction` y el `analysis` de cada partido; despues: basket pronostico publicar <fichero>")
    return 0


def _publicar(args):
    if not args:
        print(__doc__)
        return 1
    fichero = Path(args[0])
    if not fichero.exists():
        print(f"[ERROR] No existe el fichero {fichero}")
        return 1
    articulo = json.loads(fichero.read_text(encoding="utf-8"))
    problemas = previa.validar(articulo)
    if problemas:
        print("[ERROR] El borrador no se puede publicar:")
        for problema in problemas:
            print(f"  - {problema}")
        return 1
    try:
        resultado = previa.publicar(CFG, articulo)
    except RuntimeError as error:
        print(f"[ERROR] {error}")
        return 1
    print(("Artículo creado: " if resultado["nuevo"] else "Artículo actualizado: ") + resultado["id"])
    print(WEB + resultado["id"])
    return 0


if __name__ == "__main__":
    argumentos = sys.argv[1:]
    if not argumentos or argumentos[0] not in ("datos", "publicar"):
        print(__doc__)
        sys.exit(1)
    sys.exit(_datos(argumentos[1:]) if argumentos[0] == "datos" else _publicar(argumentos[1:]))
