# -*- coding: utf-8 -*-
r"""Previa y pronosticos de la proxima jornada de una liga.

Dos pasos (los lanza `basket pronostico`, ver lanzadores\pronostico.py):
  datos     lee Postgres con sql\consultas\2026-11-15_2330_previa-jornada-datos.sql,
            corta la proxima jornada, calcula margen y probabilidad de cada partido y
            escribe un borrador JSON sin textos.
  publicar  valida el borrador ya redactado y lo guarda en la coleccion
            prediction_articles de MongoDB (la que lee la web en /predictions).

Criterio numerico (csv-extra-batch\pronostico\README.md): 65 % diferencial de puntos de
la temporada, 35 % diferencial de los ultimos cinco partidos, 2,5 puntos de localia y
logistica de escala 9. La logica de calculo es pura y tiene tests en tests\test_scripts_py.py.
"""
import json
import math
import subprocess
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

PESO_TEMPORADA = 0.65
PESO_RECIENTE = 0.35
LOCALIA = 2.5
ESCALA = 9.0

WORKSPACE = Path(__file__).resolve().parents[3]
SQL_DATOS = WORKSPACE / "sql" / "consultas" / "2026-11-15_2330_previa-jornada-datos.sql"

# (pais, competicion) -> (nombre en el articulo, nombre en el titulo, prefijo del _id)
LIGAS = {
    ("europe", "euroleague"): ("EuroLeague", "Euroliga", "euroliga"),
    ("spain", "liga-endesa"): ("Liga Endesa", "Liga Endesa", "liga-endesa"),
    ("usa", "nba"): ("NBA", "NBA", "nba"),
}

METODOLOGIA = (
    "Método. Para cada equipo se calculan dos medias con sus partidos de la competición ya jugados: el "
    "diferencial de puntos de toda la temporada y el de los últimos cinco partidos. El margen esperado del "
    "local es el 65 % de la diferencia entre los diferenciales de temporada, más el 35 % de la diferencia "
    "entre los diferenciales recientes, más 2,5 puntos por jugar en casa. Ese margen se convierte en "
    "probabilidad con una curva logística de escala 9. Es el mismo criterio numérico del módulo de "
    "pronósticos del proyecto.\n\n"
    "Lectura de la confianza. Alta: 75 % o más. Media: entre el 60 % y el 75 %. Baja: menos del 60 %. Una "
    "probabilidad del 80 % significa que, en partidos con este perfil, el favorito debería perder uno de "
    "cada cinco.\n\n"
    "Límites. Las probabilidades son heurísticas y no están calibradas con temporadas anteriores. Con pocos "
    "partidos por equipo la muestra es corta, y la media de los últimos cinco se mueve mucho con un solo "
    "resultado abultado. El modelo no conoce lesiones, sanciones ni cansancio por viajes, y no distingue el "
    "rendimiento en casa y fuera de cada equipo más allá de los 2,5 puntos fijos de localía; el análisis de "
    "cada partido menciona esos balances para matizar la cifra. No se han consultado cuotas ni fuentes externas."
)


# ---------- logica pura ----------
def cortar_jornada(fixtures):
    """Devuelve los primeros partidos del calendario hasta que un equipo se repite:
    en una jornada cada equipo juega una sola vez."""
    vistos, jornada = set(), []
    for partido in fixtures:
        equipos = {partido["home_team"], partido["away_team"]}
        if equipos & vistos:
            break
        vistos |= equipos
        jornada.append(partido)
    return jornada


def margen_local(local, visitante):
    """Margen esperado del local en puntos (negativo = favorito el visitante)."""
    return (PESO_TEMPORADA * (local["dif_temp"] - visitante["dif_temp"])
            + PESO_RECIENTE * (local["dif_ult5"] - visitante["dif_ult5"])
            + LOCALIA)


def probabilidad_local(margen):
    """Probabilidad de victoria local, en tanto por ciento."""
    return 100.0 / (1.0 + math.exp(-margen / ESCALA))


def confianza(probabilidad):
    return "alta" if probabilidad >= 75 else "media" if probabilidad >= 60 else "baja"


def numero_jornada(equipos_de_la_jornada):
    """Jornada = partidos jugados por la mayoria de los equipos + 1."""
    jugados = Counter(equipo["pj"] for equipo in equipos_de_la_jornada)
    return jugados.most_common(1)[0][0] + 1


def _es(numero):
    return f"{numero:.1f}".replace(".", ",")


def pronosticar(partido, forma):
    """Partido del borrador con los numeros calculados y el analisis vacio."""
    local, visitante = forma[partido["home_team"]], forma[partido["away_team"]]
    margen = margen_local(local, visitante)
    p_local = probabilidad_local(margen)
    gana_local = p_local >= 50
    ganador = partido["home_team"] if gana_local else partido["away_team"]
    p_ganador = round(max(p_local, 100 - p_local), 1)
    return {
        "homeTeam": partido["home_team"],
        "awayTeam": partido["away_team"],
        "startsAt": partido["inicio"],
        "analysis": "",
        "prediction": (f"{'1' if gana_local else '2'} · {ganador} · 1: {_es(p_local)}% · "
                       f"2: {_es(100 - p_local)}% · margen esperado {_es(abs(margen))} puntos · "
                       f"confianza {confianza(p_ganador)}."),
        "winner": ganador,
        "winnerProbability": p_ganador,
        "sourceUrls": [],
        "_ayuda": {"local": local, "visitante": visitante, "margenLocal": round(margen, 1)},
    }


def construir_borrador(datos, pais, competicion, ahora=None):
    """Borrador del articulo a partir del JSON de la consulta. Lanza ValueError si no hay
    calendario o si algun equipo de la jornada no tiene partidos jugados."""
    jornada = cortar_jornada(datos.get("fixtures") or [])
    if not jornada:
        raise ValueError(f"No hay partidos futuros de {pais}/{competicion} en fixtures.fixtures.")
    forma = {equipo["equipo"]: equipo for equipo in datos.get("equipos") or []}
    nombres = [n for partido in jornada for n in (partido["home_team"], partido["away_team"])]
    sin_datos = sorted({n for n in nombres if n not in forma})
    if sin_datos:
        raise ValueError("Equipos de la jornada sin partidos jugados en results.results "
                         "(o con el nombre escrito distinto): " + ", ".join(sin_datos))
    nombre, titulo, prefijo = LIGAS.get((pais, competicion), (competicion, competicion, competicion))
    numero = numero_jornada([forma[n] for n in nombres])
    inicio = jornada[0]["inicio"]
    ahora = ahora or datetime.now(timezone.utc)
    return {
        "_id": f"{prefijo}-jornada-{numero}-{inicio[:10]}",
        "competition": nombre,
        "round": f"Jornada {numero}",
        "title": f"{titulo} — Jornada {numero}: previa y pronósticos",
        "introduction": "",
        "games": [pronosticar(partido, forma) for partido in jornada],
        "methodology": METODOLOGIA,
        "sources": [],
        "generatedAt": ahora.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "startsAt": inicio,
        "model": "diferencial-temporada-forma-v1 (análisis redactado por Claude)",
        "localMatches": datos.get("resultados", 0),
        "_ayuda": {
            "que_falta": "Rellenar `introduction` y el `analysis` de cada partido. Las claves `_ayuda` "
                         "no se publican.",
            "clasificacion": datos.get("equipos") or [],
        },
    }


def validar(articulo):
    """Lista de problemas que impiden publicar (vacia = se puede publicar)."""
    problemas = []
    if not (articulo.get("introduction") or "").strip():
        problemas.append("Falta la introducción (`introduction`).")
    partidos = articulo.get("games") or []
    if not partidos:
        problemas.append("El artículo no tiene partidos (`games`).")
    for partido in partidos:
        if not (partido.get("analysis") or "").strip():
            problemas.append(f"Falta el análisis de {partido.get('homeTeam')} – {partido.get('awayTeam')}.")
    for clave in ("_id", "competition", "round", "title", "methodology", "startsAt"):
        if not articulo.get(clave):
            problemas.append(f"Falta el campo `{clave}`.")
    return problemas


def limpiar(articulo):
    """Copia publicable: sin las claves `_ayuda` del borrador."""
    limpio = {k: v for k, v in articulo.items() if k != "_ayuda"}
    limpio["games"] = [{k: v for k, v in partido.items() if k != "_ayuda"}
                       for partido in articulo.get("games") or []]
    return limpio


# ---------- analisis ampliado (partido a partido) ----------
MIN_PISTA = 3      # partidos minimos en casa (o fuera) para opinar con el modelo de pista
MIN_PREVIOS = 5    # partidos previos de cada equipo para entrar en el contraste
AJUSTADO = 5       # un partido es ajustado si se decide por 5 puntos o menos


def _media(valores):
    return round(sum(valores) / len(valores), 1) if valores else None


def _fecha(texto):
    return datetime.strptime(texto, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def _ordenados(partidos):
    return sorted((p for p in partidos if p.get("inicio")), key=lambda p: (p["inicio"], p["match_id"]))


def _lados(partidos):
    """Dos entradas por partido (una por equipo), en orden cronologico."""
    for p in _ordenados(partidos):
        periodos_l, periodos_v = p.get("home_periods") or [], p.get("away_periods") or []
        yield {"equipo": p["home_team"], "rival": p["away_team"], "local": True, "inicio": p["inicio"],
               "pf": p["home_score"], "pc": p["away_score"], "qf": periodos_l, "qc": periodos_v}
        yield {"equipo": p["away_team"], "rival": p["home_team"], "local": False, "inicio": p["inicio"],
               "pf": p["away_score"], "pc": p["home_score"], "qf": periodos_v, "qc": periodos_l}


def _bloque(lados):
    return {"pj": len(lados),
            "g": sum(1 for l in lados if l["pf"] > l["pc"]),
            "p": sum(1 for l in lados if l["pf"] < l["pc"]),
            "pf": _media([l["pf"] for l in lados]),
            "pc": _media([l["pc"] for l in lados]),
            "dif": _media([l["pf"] - l["pc"] for l in lados])}


def _racha(lados):
    """Racha actual: "G3" = tres victorias seguidas; "P2" = dos derrotas seguidas."""
    if not lados:
        return None
    gana = lados[-1]["pf"] > lados[-1]["pc"]
    cuenta = 0
    for lado in reversed(lados):
        if (lado["pf"] > lado["pc"]) != gana:
            break
        cuenta += 1
    return f"{'G' if gana else 'P'}{cuenta}"


def _cuartos(lados):
    """Diferencial medio por cuarto y por mitad, solo con partidos que traen los 4 parciales."""
    completos = [l for l in lados
                 if len(l["qf"]) >= 4 and len(l["qc"]) >= 4
                 and all(v is not None for v in l["qf"][:4] + l["qc"][:4])]
    if not completos:
        return None
    por_cuarto = [_media([l["qf"][i] - l["qc"][i] for l in completos]) for i in range(4)]
    return {"partidos": len(completos),
            "q1": por_cuarto[0], "q2": por_cuarto[1], "q3": por_cuarto[2], "q4": por_cuarto[3],
            "primera_parte": _media([l["qf"][0] + l["qf"][1] - l["qc"][0] - l["qc"][1] for l in completos]),
            "segunda_parte": _media([l["qf"][2] + l["qf"][3] - l["qc"][2] - l["qc"][3] for l in completos])}


def perfil_equipos(partidos):
    """Perfil de cada equipo a partir de sus partidos jugados: balance total, en casa y
    fuera, ultimos cinco, racha, partidos ajustados, cuartos, dureza del calendario
    (diferencial medio de los rivales) y fecha del ultimo partido."""
    por_equipo = {}
    for lado in _lados(partidos):
        por_equipo.setdefault(lado["equipo"], []).append(lado)
    dif_temporada = {equipo: _media([l["pf"] - l["pc"] for l in lados]) for equipo, lados in por_equipo.items()}
    perfiles = {}
    for equipo, lados in por_equipo.items():
        ajustados = [l for l in lados if abs(l["pf"] - l["pc"]) <= AJUSTADO]
        perfiles[equipo] = {
            "total": _bloque(lados),
            "casa": _bloque([l for l in lados if l["local"]]),
            "fuera": _bloque([l for l in lados if not l["local"]]),
            "ultimos5": [f"{'G' if l['pf'] > l['pc'] else 'P'} {l['pf']}-{l['pc']} "
                         f"{'vs' if l['local'] else '@'} {l['rival']}" for l in reversed(lados[-5:])],
            "racha": _racha(lados),
            "ajustados": {"pj": len(ajustados), "g": sum(1 for l in ajustados if l["pf"] > l["pc"])},
            "cuartos": _cuartos(lados),
            "rivales_dif": _media([dif_temporada[l["rival"]] for l in lados]),
            "ultimo_partido": lados[-1]["inicio"],
        }
    return perfiles


def dias_descanso(ultimo_partido, inicio):
    """Dias entre el ultimo partido de un equipo y el siguiente."""
    return round((_fecha(inicio) - _fecha(ultimo_partido)).total_seconds() / 86400, 1)


def enfrentamientos(partidos, equipo_a, equipo_b):
    """Partidos ya jugados entre dos equipos esta temporada, del mas reciente al mas antiguo."""
    directos = [p for p in _ordenados(partidos) if {p["home_team"], p["away_team"]} == {equipo_a, equipo_b}]
    return [f"{p['inicio'][:10]}: {p['home_team']} {p['home_score']}-{p['away_score']} {p['away_team']}"
            for p in reversed(directos)]


def margen_pista(dif_casa_local, dif_fuera_visitante):
    """Segunda opinion: media entre lo que el local gana en casa y lo que el visitante
    pierde fuera. Ya incluye el efecto de la pista, asi que no suma localia."""
    if dif_casa_local is None or dif_fuera_visitante is None:
        return None
    return round((dif_casa_local - dif_fuera_visitante) / 2, 1)


def contrastar(partidos, minimo=MIN_PREVIOS):
    """Aplica el modelo a los partidos ya jugados usando solo los datos anteriores a cada
    uno. Entran los partidos en que ambos equipos tenian al menos `minimo` partidos previos.
    Devuelve aciertos, comparacion con elegir siempre al local, error del margen, puntuacion
    de Brier y aciertos por tramo de confianza y del modelo de pista."""
    historial, en_casa, fuera = {}, {}, {}
    total = aciertos = gana_local = 0
    brier = error_margen = 0.0
    tramos = {"alta": [0, 0], "media": [0, 0], "baja": [0, 0]}
    pista = {"partidos": 0, "aciertos": 0, "aciertos_modelo_en_los_mismos": 0}
    for p in _ordenados(partidos):
        local, visitante = p["home_team"], p["away_team"]
        real = p["home_score"] - p["away_score"]
        previos_l, previos_v = historial.get(local, []), historial.get(visitante, [])
        if len(previos_l) >= minimo and len(previos_v) >= minimo:
            margen = margen_local(
                {"dif_temp": sum(previos_l) / len(previos_l), "dif_ult5": sum(previos_l[-5:]) / len(previos_l[-5:])},
                {"dif_temp": sum(previos_v) / len(previos_v), "dif_ult5": sum(previos_v[-5:]) / len(previos_v[-5:])})
            probabilidad = probabilidad_local(margen)
            acierta = (margen >= 0) == (real > 0)
            total += 1
            aciertos += acierta
            gana_local += real > 0
            brier += (probabilidad / 100 - (1 if real > 0 else 0)) ** 2
            error_margen += abs(margen - real)
            tramo = tramos[confianza(max(probabilidad, 100 - probabilidad))]
            tramo[0] += 1
            tramo[1] += acierta
            casa_l, fuera_v = en_casa.get(local, []), fuera.get(visitante, [])
            if len(casa_l) >= MIN_PISTA and len(fuera_v) >= MIN_PISTA:
                alternativo = margen_pista(sum(casa_l) / len(casa_l), sum(fuera_v) / len(fuera_v))
                pista["partidos"] += 1
                pista["aciertos"] += (alternativo >= 0) == (real > 0)
                pista["aciertos_modelo_en_los_mismos"] += acierta
        historial.setdefault(local, []).append(real)
        historial.setdefault(visitante, []).append(-real)
        en_casa.setdefault(local, []).append(real)
        fuera.setdefault(visitante, []).append(-real)
    if not total:
        return {"partidos": 0}
    return {"partidos": total,
            "aciertos": aciertos,
            "porcentaje": round(100 * aciertos / total, 1),
            "porcentaje_siempre_local": round(100 * gana_local / total, 1),
            "error_medio_margen": round(error_margen / total, 1),
            "brier": round(brier / total, 3),
            "por_confianza": {nombre: {"partidos": n, "aciertos": a} for nombre, (n, a) in tramos.items()},
            "modelo_pista": pista}


def texto_contraste(contraste):
    """Parrafo de metodologia con el resultado del contraste (vacio si no hay muestra)."""
    if not contraste or not contraste.get("partidos"):
        return ""
    tramos = contraste["por_confianza"]
    detalle = ", ".join(f"confianza {nombre}: {tramos[nombre]['aciertos']} de {tramos[nombre]['partidos']}"
                        for nombre in ("alta", "media", "baja") if tramos[nombre]["partidos"])
    return (f"Contraste con la temporada. Aplicado a los {contraste['partidos']} partidos ya jugados en los que "
            f"ambos equipos tenían al menos {MIN_PREVIOS} partidos previos, y usando solo los datos anteriores a "
            f"cada uno, el modelo acertó el ganador en {contraste['aciertos']} "
            f"({_es(contraste['porcentaje'])} %). Elegir siempre al equipo local habría acertado el "
            f"{_es(contraste['porcentaje_siempre_local'])} %. Por tramos: {detalle}. El error medio del margen "
            f"fue de {_es(contraste['error_medio_margen'])} puntos. Es una muestra pequeña y de una sola "
            f"temporada: sirve para orientarse sobre cuánto fiarse del modelo, no para darlo por calibrado.")


def ampliar(borrador, partidos):
    """Añade al borrador el analisis ampliado: perfiles, descanso, directos, segunda
    opinion por pista y contraste del modelo. Modifica y devuelve el borrador."""
    perfiles = perfil_equipos(partidos)
    for partido in borrador["games"]:
        local, visitante = perfiles.get(partido["homeTeam"]), perfiles.get(partido["awayTeam"])
        if not local or not visitante:
            continue
        casa, fuera = local["casa"], visitante["fuera"]
        partido["_ayuda"].update({
            "perfilLocal": local,
            "perfilVisitante": visitante,
            "descansoLocalDias": dias_descanso(local["ultimo_partido"], partido["startsAt"]),
            "descansoVisitanteDias": dias_descanso(visitante["ultimo_partido"], partido["startsAt"]),
            "enfrentamientosEstaTemporada": enfrentamientos(partidos, partido["homeTeam"], partido["awayTeam"]),
            "margenPistaLocal": margen_pista(casa["dif"] if casa["pj"] >= MIN_PISTA else None,
                                             fuera["dif"] if fuera["pj"] >= MIN_PISTA else None),
        })
    contraste = contrastar(partidos)
    borrador["_ayuda"]["contraste"] = contraste
    parrafo = texto_contraste(contraste)
    if parrafo:
        borrador["methodology"] = borrador["methodology"] + "\n\n" + parrafo
    return borrador


# ---------- entrada y salida ----------
SQL_PARTIDOS = WORKSPACE / "sql" / "consultas" / "2026-11-15_2345_previa-jornada-partidos.sql"


def _consulta_json(cfg, fichero, pais, competicion):
    proceso = subprocess.run(
        ["docker", "exec", "-i", cfg.get("POSTGRES_CONTAINER", "local-validation-postgres-1"),
         "psql", "-U", cfg.get("DB_USER", "test"), "-d", cfg.get("DB_NAME", "basketball"),
         "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1",
         "-v", f"pais={pais}", "-v", f"competicion={competicion}"],
        input=fichero.read_bytes(), capture_output=True)
    if proceso.returncode != 0:
        raise RuntimeError(f"La consulta {fichero.name} falló: " + proceso.stderr.decode("utf-8", "replace").strip())
    return json.loads(proceso.stdout.decode("utf-8"))


def leer_partidos(cfg, pais, competicion):
    """Partidos jugados de la liga, con parciales (para el analisis ampliado)."""
    return _consulta_json(cfg, SQL_PARTIDOS, pais, competicion)


def leer_datos(cfg, pais, competicion):
    """Ejecuta la consulta guardada y devuelve su JSON."""
    return _consulta_json(cfg, SQL_DATOS, pais, competicion)


_UPSERT_JS = """
const d = JSON.parse(fs.readFileSync("/tmp/previa-jornada.json", "utf8"));
const previo = db.prediction_articles.findOne({
  competition: d.competition, round: d.round,
  startsAt: { $regex: "^" + d.startsAt.slice(0, 10) }, _id: { $not: /-review$/ } });
if (previo) d._id = previo._id;
const r = db.prediction_articles.replaceOne({ _id: d._id }, d, { upsert: true });
print(JSON.stringify({ id: d._id, nuevo: r.upsertedCount === 1 }));
"""


def publicar(cfg, articulo):
    """Guarda el articulo en MongoDB. Si ya hay uno de esa competicion, jornada y fecha de
    inicio, lo actualiza con su mismo _id. Devuelve {"id": ..., "nuevo": bool}."""
    contenedor = cfg.get("MONGO_CONTAINER", "local-validation-mongo-1")
    with tempfile.TemporaryDirectory() as carpeta:
        fichero = Path(carpeta) / "previa-jornada.json"
        fichero.write_text(json.dumps(limpiar(articulo), ensure_ascii=False), encoding="utf-8")
        copia = subprocess.run(["docker", "cp", str(fichero), f"{contenedor}:/tmp/previa-jornada.json"],
                               capture_output=True, text=True)
        if copia.returncode != 0:
            raise RuntimeError("No se pudo copiar el artículo al contenedor de Mongo: " + copia.stderr.strip())
    proceso = subprocess.run(
        ["docker", "exec", "-i", contenedor, "mongosh", "--quiet", cfg.get("MONGO_DB", "basketball"),
         "--eval", _UPSERT_JS], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proceso.returncode != 0:
        raise RuntimeError("MongoDB rechazó el artículo: " + (proceso.stderr or proceso.stdout).strip())
    return json.loads(proceso.stdout.strip().splitlines()[-1])
