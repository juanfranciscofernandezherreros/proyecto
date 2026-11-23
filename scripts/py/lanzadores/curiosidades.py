# -*- coding: utf-8 -*-
r"""Lanzador: publica en MongoDB las curiosidades ampliadas para la web.

Uso: basket curiosidades

Ejecuta en Postgres la consulta ya validada
   sql\consultas\2026-11-23_1400_curiosidades-ampliadas.sql
(una fila por curiosidad, con nivel, de la mas nueva a la mas antigua, sin la
pretemporada de la NBA) y reemplaza con ella la coleccion `curiosity_feed` de Mongo,
que sirve la API en GET /api/v1/curiosities/feed. La API solo lee Mongo (SDD), por eso
se publica igual que los pronosticos. resultados-ayer lo lanza al terminar.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from _base import CFG, WORKSPACE, ensure

SQL = WORKSPACE / "sql" / "consultas" / "2026-11-23_1400_curiosidades-ampliadas.sql"
SEPARADOR = "\x1f"
COLUMNAS = ("fecha", "nivel", "liga", "partido", "tipo", "detalle", "match_id")
COLECCION = "curiosity_feed"

_REEMPLAZAR_JS = """
const docs = JSON.parse(fs.readFileSync("/tmp/curiosity-feed.json", "utf8"));
db.%s.deleteMany({});
if (docs.length) db.%s.insertMany(docs);
db.%s.createIndex({ rank: 1 });
print(JSON.stringify({ total: db.%s.countDocuments({}) }));
""" % ((COLECCION,) * 4)


def parsear(texto):
    """Filas de `psql -t -A -F <US>` -> lista de dicts con COLUMNAS (en el orden de la consulta)."""
    filas = []
    for linea in texto.splitlines():
        if not linea.strip():
            continue
        partes = linea.split(SEPARADOR)
        if len(partes) != len(COLUMNAS):
            raise ValueError(f"fila con {len(partes)} columnas en vez de {len(COLUMNAS)}: {linea[:120]}")
        filas.append(dict(zip(COLUMNAS, partes)))
    return filas


def documentos(filas):
    """Documentos de Mongo: rank = posicion (0 = la mas nueva), fecha ISO, nivel entero."""
    docs = []
    for rank, f in enumerate(filas):
        dia, mes, anio = f["fecha"].split("/")
        docs.append({
            "_id": f"{rank:05d}-{f['match_id']}-{f['tipo']}",
            "rank": rank,
            "date": f"{anio}-{mes}-{dia}",
            "level": int(f["nivel"]),
            "competition": f["liga"],
            "match": f["partido"],
            "type": f["tipo"],
            "detail": f["detalle"],
            "matchId": f["match_id"],
        })
    return docs


def leer_postgres():
    cmd = ["docker", "exec", "-i", CFG.get("POSTGRES_CONTAINER"), "psql", "-U", CFG.get("DB_USER"),
           "-d", CFG.get("DB_NAME"), "-X", "-q", "-t", "-A", "-F", SEPARADOR, "-v", "ON_ERROR_STOP=1"]
    proceso = subprocess.run(cmd, input=SQL.read_bytes(), capture_output=True)
    if proceso.returncode != 0:
        raise RuntimeError(f"La consulta {SQL.name} falló: "
                           + proceso.stderr.decode("utf-8", "replace").strip())
    return parsear(proceso.stdout.decode("utf-8"))


def publicar(docs):
    contenedor = CFG.get("MONGO_CONTAINER", "local-validation-mongo-1")
    with tempfile.TemporaryDirectory() as carpeta:
        fichero = Path(carpeta) / "curiosity-feed.json"
        fichero.write_text(json.dumps(docs, ensure_ascii=False), encoding="utf-8")
        copia = subprocess.run(["docker", "cp", str(fichero), f"{contenedor}:/tmp/curiosity-feed.json"],
                               capture_output=True, text=True)
        if copia.returncode != 0:
            raise RuntimeError("No se pudo copiar el fichero al contenedor de Mongo: " + copia.stderr.strip())
    proceso = subprocess.run(
        ["docker", "exec", "-i", contenedor, "mongosh", "--quiet", CFG.get("MONGO_DB", "basketball"),
         "--eval", _REEMPLAZAR_JS], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proceso.returncode != 0:
        raise RuntimeError("MongoDB rechazó las curiosidades: " + (proceso.stderr or proceso.stdout).strip())
    return json.loads(proceso.stdout.strip().splitlines()[-1])["total"]


def main(argv=None):
    if ensure("postgres"):
        print("ERROR: Postgres no responde.")
        return 1
    try:
        docs = documentos(leer_postgres())
        total = publicar(docs)
    except (ValueError, RuntimeError) as error:
        print(f"[ERROR] {error}")
        return 1
    por_nivel = {n: sum(1 for d in docs if d["level"] == n) for n in (3, 2, 1)}
    ultima = docs[0]["date"] if docs else "-"
    print(f"Curiosidades publicadas en Mongo ({COLECCION}): {total} "
          f"(nivel 3: {por_nivel[3]}, nivel 2: {por_nivel[2]}, nivel 1: {por_nivel[1]}); "
          f"la más nueva del {ultima}.")
    return 0 if total == len(docs) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
