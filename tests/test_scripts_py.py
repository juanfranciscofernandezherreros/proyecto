# -*- coding: utf-8 -*-
"""Tests unitarios de la logica pura de scripts\\py (sin Postgres, sin Flashscore).

Ejecutar:  python -m unittest discover -s tests -v
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "scripts" / "py"))
sys.path.insert(0, str(RAIZ / "scripts" / "py" / "extraer"))

import config
import proc
from ligas import catalogo, matchday
import reextraer


def _fila(fecha, local, visitante):
    return {"eventDatetime": fecha, "homeTeam": local, "awayTeam": visitante}


class UltimaJornadaTests(unittest.TestCase):
    def test_corta_cuando_un_equipo_se_repite(self):
        filas = [
            _fila("2026-11-10T20:00:00+01:00", "A", "B"),
            _fila("2026-11-09T20:00:00+01:00", "C", "D"),
            _fila("2026-11-05T20:00:00+01:00", "A", "C"),  # A y C ya vistos: otra jornada
        ]
        jornada = matchday.ultima_jornada(filas)
        self.assertEqual([(r["homeTeam"], r["awayTeam"]) for r in jornada], [("A", "B"), ("C", "D")])

    def test_ignora_filas_sin_fecha_y_no_distingue_mayusculas(self):
        filas = [
            _fila("2026-11-10T20:00:00+01:00", "Real Madrid", "Barcelona"),
            _fila("", "X", "Y"),
            _fila("2026-11-08T20:00:00+01:00", "REAL MADRID", "Baskonia"),
        ]
        self.assertEqual(len(matchday.ultima_jornada(filas)), 1)

    def test_sin_fechas_lanza_error(self):
        with self.assertRaises(ValueError):
            matchday.ultima_jornada([_fila("", "A", "B")])


class ValidarLimiteTests(unittest.TestCase):
    def test_valores_validos_y_por_defecto(self):
        self.assertEqual(proc.validar_limite("25"), 25)
        self.assertEqual(proc.validar_limite("", 7), 7)
        self.assertEqual(proc.validar_limite(None, 7), 7)

    def test_rechaza_texto_y_negativos(self):
        with self.assertRaises(ValueError):
            proc.validar_limite("diez")
        with self.assertRaises(ValueError):
            proc.validar_limite("-1")


class CatalogoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ruta = Path(self.tmp.name) / "ligas.json"
        self.ruta.write_text(json.dumps([
            {"code": "EUROLIGA", "country": "europe", "competition": "euroleague"},
            {"code": "ACB", "country": "spain", "competition": "liga-endesa"},
        ]), encoding="utf-8")
        self.cfg = config.cargar()
        self.previo = {k: self.cfg.get(k) for k in ("FILTRO_PAIS", "FILTRO_COMPETICION")}
        self.cfg["FILTRO_PAIS"] = ""
        self.cfg["FILTRO_COMPETICION"] = ""

    def tearDown(self):
        self.cfg.update(self.previo)
        self.tmp.cleanup()

    def test_all_devuelve_todas_y_un_code_solo_la_suya(self):
        self.assertEqual(len(catalogo.seleccionar("ALL", self.ruta)), 2)
        self.assertEqual([lg["code"] for lg in catalogo.seleccionar("ACB", self.ruta)], ["ACB"])

    def test_liga_inexistente_lanza_error(self):
        with self.assertRaises(ValueError):
            catalogo.seleccionar("NOEXISTE", self.ruta)

    def test_filtro_de_pais(self):
        self.cfg["FILTRO_PAIS"] = "spain"
        self.assertEqual([lg["code"] for lg in catalogo.seleccionar("ALL", self.ruta)], ["ACB"])
        with self.assertRaises(ValueError):
            catalogo.seleccionar("EUROLIGA", self.ruta)

    def test_catalogo_real_tiene_codigos_unicos_y_campos_obligatorios(self):
        ligas = json.loads((RAIZ / "LIGAS_BASKET.json").read_text(encoding="utf-8"))
        codigos = [lg["code"] for lg in ligas]
        self.assertEqual(len(codigos), len(set(codigos)))
        for lg in ligas:
            for campo in ("code", "country", "competition", "resultsUrl"):
                self.assertTrue(lg.get(campo), f"{lg.get('code')}: falta {campo}")


class ReextraerArgumentosTests(unittest.TestCase):
    def test_por_defecto_todos_los_datasets_y_sin_duplicados(self):
        ids, nombres, progreso = reextraer._argumentos(["juVOVk74", "IRWGXBxh", "juVOVk74"])
        self.assertEqual(ids, ["juVOVk74", "IRWGXBxh"])
        self.assertEqual(nombres, ["equipo", "jugadores", "resumen", "jugadas"])
        self.assertIsNone(progreso)

    def test_dataset_fichero_y_progreso(self):
        with tempfile.TemporaryDirectory() as d:
            lista = Path(d) / "lista.txt"
            lista.write_text("juVOVk74|europe|euroleague\n\nIRWGXBxh\n", encoding="utf-8")
            ids, nombres, progreso = reextraer._argumentos(
                ["--dataset", "EQUIPO", "--fichero", str(lista), "--progreso", str(Path(d) / "p.txt")])
        self.assertEqual(ids, ["juVOVk74", "IRWGXBxh"])
        self.assertEqual(nombres, ["equipo"])
        self.assertEqual(progreso.name, "p.txt")

    def test_errores(self):
        for args in ([], ["--dataset", "nada", "juVOVk74"], ["mal id;"], ["--progreso"],
                     ["--fichero", "no-existe.txt"], ["x'; DROP TABLE t; --"]):
            with self.assertRaises(ValueError, msg=str(args)):
                reextraer._argumentos(args)


class ReextraerProgresoTests(unittest.TestCase):
    def test_solo_cuenta_lo_anotado_como_ok(self):
        with tempfile.TemporaryDirectory() as d:
            progreso = Path(d) / "p.txt"
            reextraer._anotar(progreso, "aaaa1111", "TEAM_STATS", "OK", "f.csv")
            reextraer._anotar(progreso, "bbbb2222", "TEAM_STATS", "FALLO", "sin URL")
            self.assertEqual(reextraer._leer_progreso(progreso), {("aaaa1111", "TEAM_STATS")})

    def test_sin_fichero_no_hay_progreso(self):
        self.assertEqual(reextraer._leer_progreso(None), set())
        self.assertEqual(reextraer._leer_progreso(Path("no-existe-progreso.txt")), set())


class ConfigTests(unittest.TestCase):
    def test_exporta_el_driver_de_edge_al_entorno(self):
        cfg = config.cargar()
        if cfg.get("EDGEDRIVER_PATH"):
            self.assertTrue(os.environ.get("EDGEDRIVER_PATH"))
        if cfg.get("FLASHSCORE_BROWSER"):
            self.assertTrue(os.environ.get("FLASHSCORE_BROWSER"))

    def test_resuelve_las_claves_compuestas(self):
        cfg = config.cargar()
        self.assertNotIn("${", cfg["COMPETITIONS_DIR"])
        self.assertTrue(cfg["COMPETITIONS_DIR"].startswith(cfg["DATA_DIR"]))


class DatosAyerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import datos_ayer
        cls.datos_ayer = datos_ayer

    def test_consulta_de_ayer_usa_fecha_local_de_madrid(self):
        sql = self.datos_ayer.consulta()
        self.assertIn("fixtures.fixtures", sql)
        self.assertIn("Europe/Madrid", sql)
        self.assertIn("- 1)", sql)

    def test_consulta_con_fecha_explicita(self):
        self.assertIn("DATE '2026-11-16'", self.datos_ayer.consulta("2026-11-16"))

    def test_paso_previo_se_puede_desactivar(self):
        self.assertTrue(self.datos_ayer.activo({}, {}))
        self.assertFalse(self.datos_ayer.activo({"SKIP_DATOS_AYER": "1"}, {}))
        self.assertFalse(self.datos_ayer.activo({}, {"DATOS_AYER": "0"}))
        self.assertTrue(self.datos_ayer.activo({}, {"DATOS_AYER": "1"}))

    def test_fecha_invalida_se_rechaza(self):
        for mala in ("16/11/2026", "2026-13-40", "2026-11-16'; DROP TABLE x;--"):
            with self.assertRaises(ValueError):
                self.datos_ayer.consulta(mala)


if __name__ == "__main__":
    unittest.main()


class RunTeeTests(unittest.TestCase):
    """_run_tee no debe caerse si la consola es cp1252 (fallo de nov-2026 en la BSL)."""

    def _consola_cp1252(self):
        import io
        bruto = io.BytesIO()
        return bruto, io.TextIOWrapper(bruto, encoding="cp1252", errors="strict", newline="")

    def test_escribir_consola_sustituye_lo_que_no_cabe(self):
        import dataset
        bruto, consola = self._consola_cp1252()
        dataset._escribir_consola("Bağcılar � ok\n", consola)
        consola.flush()
        self.assertEqual(bruto.getvalue().decode("cp1252"), "Ba?c?lar ? ok\n")

    def test_run_tee_completa_y_el_log_guarda_utf8(self):
        import dataset
        _, consola = self._consola_cp1252()
        with tempfile.TemporaryDirectory() as d:
            log = Path(d) / "x.log"
            cmd = [sys.executable, "-c",
                   r"import sys; sys.stdout.buffer.write(b'\xc5\x9eehir\n')"]
            original = sys.stdout
            sys.stdout = consola
            try:
                rc = dataset._run_tee(cmd, log)
            finally:
                sys.stdout = original
            self.assertEqual(rc, 0)
            self.assertEqual(log.read_text(encoding="utf-8"), "Şehir\n")
