# -*- coding: utf-8 -*-
r"""Carga y seleccion de ligas de LIGAS_BASKET.json (parte compartida de los
orquestadores de ligas), con los filtros FILTRO_PAIS / FILTRO_COMPETICION.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config as _config


def cargar_ligas(config_path=None):
    cfg = _config.cargar()
    ruta = Path(config_path) if config_path else Path(cfg["LEAGUE_CATALOG"])
    datos = json.loads(ruta.read_text(encoding="utf-8"))
    return datos if isinstance(datos, list) else [datos]


def seleccionar(league="ALL", config_path=None):
    """Devuelve las ligas pedidas (ALL o un code), ya aplicados FILTRO_PAIS/COMPETICION.
    Lanza ValueError si la seleccion queda vacia."""
    cfg = _config.cargar()
    ligas = cargar_ligas(config_path)
    want_all = league.strip().upper() == "ALL"
    sel = [lg for lg in ligas if want_all or str(lg.get("code", "")).strip() == league.strip()]
    if not sel:
        raise ValueError(f"Liga no encontrada: {league}")

    paises = [x.strip() for x in str(cfg.get("FILTRO_PAIS", "")).split(",") if x.strip()]
    comps = [x.strip() for x in str(cfg.get("FILTRO_COMPETICION", "")).split(",") if x.strip()]
    sel = [lg for lg in sel
           if (not paises or lg.get("country") in paises)
           and (not comps or lg.get("competition") in comps)]
    if not sel:
        raise ValueError(f"Ninguna liga cumple FILTRO_PAIS='{cfg.get('FILTRO_PAIS')}' y "
                         f"FILTRO_COMPETICION='{cfg.get('FILTRO_COMPETICION')}'.")
    if paises or comps:
        print(f"Ligas filtradas: {', '.join(lg.get('code') for lg in sel)}")
    return sel


def por_code(league):
    """Una liga por su code (None si no existe)."""
    code = league.strip().upper()
    for lg in cargar_ligas():
        if str(lg.get("code", "")).upper() == code:
            return lg
    return None
