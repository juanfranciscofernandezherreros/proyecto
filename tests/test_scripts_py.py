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


def _equipo(nombre, dif_temp, dif_ult5, pj=11):
    return {"equipo": nombre, "pj": pj, "g": 0, "p": 0, "pf": 0, "pc": 0, "dif_temp": dif_temp,
            "dif_ult5": dif_ult5, "g_ult5": 0, "casa": "0-0", "fuera": "0-0"}


def _partido(inicio, local, visitante):
    return {"match_id": f"{local}-{visitante}", "inicio": inicio, "home_team": local, "away_team": visitante}


class PronosticoPreviaTests(unittest.TestCase):
    """Logica pura de scripts\\py\\pronostico\\previa.py (sin Postgres ni Mongo)."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "pronostico"))
        import previa
        cls.previa = previa

    def _datos(self):
        return {
            "fixtures": [
                _partido("2026-11-17T18:00:00Z", "Zalgiris Kaunas", "Bayern"),
                _partido("2026-11-17T19:45:00Z", "Partizan Mozzart Bet", "Valencia"),
                _partido("2026-11-19T19:00:00Z", "Zalgiris Kaunas", "Panathinaikos"),
            ],
            "equipos": [
                _equipo("Zalgiris Kaunas", 3.3, 12.6), _equipo("Bayern", -8.4, -12.2),
                _equipo("Partizan Mozzart Bet", 1.7, 4.8), _equipo("Valencia", 7.5, 8.2),
                _equipo("Panathinaikos", 7.9, -0.6),
            ],
            "resultados": 110,
        }

    def test_la_jornada_se_corta_cuando_un_equipo_se_repite(self):
        jornada = self.previa.cortar_jornada(self._datos()["fixtures"])
        self.assertEqual([p["home_team"] for p in jornada], ["Zalgiris Kaunas", "Partizan Mozzart Bet"])

    def test_margen_y_probabilidad_del_local(self):
        margen = self.previa.margen_local(_equipo("L", 3.3, 12.6), _equipo("V", -8.4, -12.2))
        self.assertAlmostEqual(margen, 18.785, places=3)
        self.assertAlmostEqual(self.previa.probabilidad_local(margen), 89.0, places=1)
        self.assertAlmostEqual(self.previa.probabilidad_local(0), 50.0, places=6)

    def test_confianza_por_tramos(self):
        self.assertEqual(self.previa.confianza(75.0), "alta")
        self.assertEqual(self.previa.confianza(74.9), "media")
        self.assertEqual(self.previa.confianza(60.0), "media")
        self.assertEqual(self.previa.confianza(59.9), "baja")

    def test_borrador_elige_al_visitante_cuando_es_favorito(self):
        borrador = self.previa.construir_borrador(self._datos(), "europe", "euroleague")
        self.assertEqual(borrador["_id"], "euroliga-jornada-12-2026-11-17")
        self.assertEqual(borrador["round"], "Jornada 12")
        self.assertEqual(borrador["competition"], "EuroLeague")
        partizan = borrador["games"][1]
        self.assertEqual(partizan["winner"], "Valencia")
        self.assertEqual(partizan["winnerProbability"], 56.8)
        self.assertTrue(partizan["prediction"].startswith("2 · Valencia · 1: 43,2% · 2: 56,8%"))

    def test_borrador_falla_sin_calendario_o_con_un_equipo_sin_resultados(self):
        with self.assertRaises(ValueError):
            self.previa.construir_borrador({"fixtures": [], "equipos": []}, "europe", "euroleague")
        datos = self._datos()
        datos["equipos"] = [e for e in datos["equipos"] if e["equipo"] != "Bayern"]
        with self.assertRaisesRegex(ValueError, "Bayern"):
            self.previa.construir_borrador(datos, "europe", "euroleague")

    def test_validar_exige_textos_y_limpiar_quita_la_ayuda(self):
        borrador = self.previa.construir_borrador(self._datos(), "europe", "euroleague")
        self.assertEqual(len(self.previa.validar(borrador)), 3)  # introduccion + 2 analisis
        borrador["introduction"] = "Texto"
        for partido in borrador["games"]:
            partido["analysis"] = "Texto"
        self.assertEqual(self.previa.validar(borrador), [])
        limpio = self.previa.limpiar(borrador)
        self.assertNotIn("_ayuda", limpio)
        self.assertNotIn("_ayuda", limpio["games"][0])
        self.assertIn("_ayuda", borrador)  # el borrador original no se toca


    # ----- analisis ampliado -----
    def _jugados(self):
        def jugado(ident, inicio, local, visitante, pl, pv, ql=None, qv=None):
            return {"match_id": ident, "inicio": inicio, "home_team": local, "away_team": visitante,
                    "home_score": pl, "away_score": pv, "home_periods": ql or [], "away_periods": qv or []}
        return [
            jugado("m1", "2026-10-01T18:00:00Z", "A", "B", 80, 70, [20, 20, 20, 20, None], [10, 20, 20, 20, None]),
            jugado("m2", "2026-10-08T18:00:00Z", "B", "A", 90, 85, [25, 25, 20, 20, None], [20, 20, 25, 20, None]),
            jugado("m3", "2026-10-15T18:00:00Z", "A", "C", 70, 72),
        ]

    def test_perfil_separa_casa_y_fuera_y_calcula_racha_ajustados_y_cuartos(self):
        perfil = self.previa.perfil_equipos(self._jugados())["A"]
        self.assertEqual((perfil["total"]["pj"], perfil["total"]["g"], perfil["total"]["p"]), (3, 1, 2))
        self.assertEqual((perfil["casa"]["pj"], perfil["casa"]["dif"]), (2, 4.0))
        self.assertEqual((perfil["fuera"]["pj"], perfil["fuera"]["dif"]), (1, -5.0))
        self.assertEqual(perfil["racha"], "P2")
        self.assertEqual(perfil["ajustados"], {"pj": 2, "g": 0})
        self.assertEqual(perfil["ultimos5"][0], "P 70-72 vs C")
        self.assertEqual(perfil["cuartos"]["partidos"], 2)  # m3 no trae parciales
        self.assertEqual(perfil["cuartos"]["q1"], 2.5)
        self.assertEqual(perfil["ultimo_partido"], "2026-10-15T18:00:00Z")

    def test_descanso_directos_y_margen_de_pista(self):
        self.assertEqual(self.previa.dias_descanso("2026-10-15T18:00:00Z", "2026-10-17T18:00:00Z"), 2.0)
        self.assertEqual(self.previa.enfrentamientos(self._jugados(), "A", "B"),
                         ["2026-10-08: B 90-85 A", "2026-10-01: A 80-70 B"])
        self.assertEqual(self.previa.margen_pista(4.0, -6.0), 5.0)
        self.assertIsNone(self.previa.margen_pista(None, -6.0))

    def test_contraste_usa_solo_partidos_anteriores(self):
        contraste = self.previa.contrastar(self._jugados(), minimo=1)
        # m1 y m3 no entran (algun equipo sin partidos previos); en m2 el modelo elige a A y gana B.
        self.assertEqual((contraste["partidos"], contraste["aciertos"]), (1, 0))
        self.assertEqual(contraste["porcentaje_siempre_local"], 100.0)
        self.assertEqual(contraste["error_medio_margen"], 22.5)
        self.assertEqual(self.previa.contrastar(self._jugados())["partidos"], 0)

    def test_ampliar_añade_la_ayuda_y_el_parrafo_de_contraste(self):
        datos = {"fixtures": [_partido("2026-10-20T18:00:00Z", "A", "B")],
                 "equipos": [_equipo("A", 1.0, 1.0, pj=3), _equipo("B", -2.5, -2.5, pj=2)], "resultados": 3}
        borrador = self.previa.construir_borrador(datos, "europe", "euroleague")
        antes = borrador["methodology"]
        self.previa.ampliar(borrador, self._jugados())
        ayuda = borrador["games"][0]["_ayuda"]
        self.assertEqual(ayuda["descansoLocalDias"], 5.0)
        self.assertEqual(ayuda["descansoVisitanteDias"], 12.0)
        self.assertEqual(len(ayuda["enfrentamientosEstaTemporada"]), 2)
        self.assertIsNone(ayuda["margenPistaLocal"])  # menos de 3 partidos en casa o fuera
        self.assertEqual(borrador["methodology"], antes)  # sin muestra no se añade el parrafo
        self.assertIn("38 (63,3 %)", self.previa.texto_contraste(
            {"partidos": 60, "aciertos": 38, "porcentaje": 63.3, "porcentaje_siempre_local": 53.3,
             "error_medio_margen": 10.0,
             "por_confianza": {"alta": {"partidos": 19, "aciertos": 14}, "media": {"partidos": 28, "aciertos": 18},
                               "baja": {"partidos": 13, "aciertos": 6}}}))


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


class BasketLogsTests(unittest.TestCase):
    """basket: log por ejecucion para promtail (job basket) y dashboard basket-logs."""

    def test_nombre_del_log_casa_con_la_regex_de_promtail(self):
        import re
        from datetime import datetime
        import basket
        log = basket.fichero_log("resultados-ayer", datetime(2026, 11, 17, 9, 48, 4))
        self.assertEqual(log.name, "resultados-ayer_20261117_094804.log")
        self.assertEqual(log.parent.parts[-2:], ("logs", "basket"))
        promtail = (RAIZ / "local-validation" / "observability" / "promtail.yml").read_text(encoding="utf-8")
        regex = re.search(r"expression: '(.+)'", promtail).group(1)
        m = re.search(regex, "/var/log/basketball/basket/" + log.name)
        self.assertEqual((m.group("comando"), m.group("ejecucion")),
                         ("resultados-ayer", "resultados-ayer_20261117_094804"))

    def test_estado_no_levanta_grafana(self):
        import basket
        self.assertIn("estado", basket.SIN_OBSERVABILIDAD)
        self.assertNotIn("resultados-ayer", basket.SIN_OBSERVABILIDAD)

    def test_dashboard_basket_logs_valido(self):
        ruta = RAIZ / "local-validation" / "observability" / "basket-logs-dashboard.json"
        d = json.loads(ruta.read_text(encoding="utf-8"))
        self.assertEqual(d["dashboard"]["uid"], "basket-logs")
        self.assertTrue(d["overwrite"])
        for panel in d["dashboard"]["panels"]:
            self.assertEqual(panel["datasource"]["uid"], "loki-local")

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


class CuadrarDiaTests(unittest.TestCase):
    """Logica pura de basket cuadrar (Flashscore / fixtures / Mongo)."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import cuadrar_dia
        cls.m = cuadrar_dia

    def test_filas_del_dia_usa_la_hora_de_madrid(self):
        from datetime import date
        filas = [
            {"matchId": "a", "eventDatetime": "2026-11-16T00:30:00+01:00", "homeTeam": "X",
             "awayTeam": "Y", "homeScore": "90", "awayScore": "80"},
            {"matchId": "b", "eventDatetime": "2026-11-15T23:30:00+00:00", "homeTeam": "X",
             "awayTeam": "Y", "homeScore": "1", "awayScore": "2"},
            {"matchId": "c", "eventDatetime": "2026-11-15T22:00:00+01:00", "homeTeam": "X",
             "awayTeam": "Y", "homeScore": "1", "awayScore": "2"},
            {"matchId": "d", "eventDatetime": "", "homeTeam": "X", "awayTeam": "Y"},
        ]
        r = self.m.filas_del_dia(filas, date(2026, 11, 16))
        self.assertEqual(sorted(r), ["a", "b"])
        self.assertEqual(r["a"]["marcador"], (90, 80))

    def test_todo_cuadra(self):
        fs = {"a": {"liga": "l", "local": "X", "visitante": "Y", "marcador": (90, 80)}}
        fx = {"a": {"liga": "l", "local": "X", "visitante": "Y"}}
        mg = {"a": {"marcador": (90, 80), "secciones": list(self.m.SECCIONES)}}
        self.assertEqual(self.m.cuadrar(fs, fx, mg)[0]["problemas"], [])

    def test_detecta_cada_problema(self):
        fs = {"a": {"liga": "l", "local": "X", "visitante": "Y", "marcador": (90, 80)},
              "b": {"liga": "l", "local": "X", "visitante": "Y", "marcador": (1, 2)}}
        fx = {"a": {"liga": "l", "local": "X", "visitante": "Y"},
              "c": {"liga": "l", "local": "X", "visitante": "Y"}}
        mg = {"a": {"marcador": (91, 80), "secciones": ["fixture", "result"]}}
        r = {f["match_id"]: f["problemas"] for f in self.m.cuadrar(fs, fx, mg)}
        self.assertIn("marcador distinto en Mongo", r["a"])
        self.assertTrue(any(p.startswith("faltan secciones: summary") for p in r["a"]))
        self.assertEqual(r["b"], ["no esta en fixtures", "no esta en Mongo"])
        self.assertEqual(r["c"], ["no esta en Flashscore", "no esta en Mongo"])

    def test_fecha(self):
        from datetime import date
        self.assertEqual(self.m.validar_fecha("2026-11-16"), date(2026, 11, 16))
        with self.assertRaises(ValueError):
            self.m.validar_fecha("16-11-2026")
        self.assertIsInstance(self.m.validar_fecha(None), date)


class ResultadosAyerTests(unittest.TestCase):
    """basket resultados-ayer: filtrado por dia y nombre RESULTS_YESTERDAY."""

    def test_filtra_el_dia_y_pone_la_liga_delante(self):
        from datetime import date
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import resultados_ayer as R
        filas = [{"matchId": "a", "eventDatetime": "2026-11-16T03:00:00+01:00"},
                 {"matchId": "b", "eventDatetime": "2026-11-17T03:00:00+01:00"},
                 {"matchId": "c", "eventDatetime": ""}]
        r = R.filas_de_liga(filas, date(2026, 11, 16), "usa", "nba")
        self.assertEqual([f["matchId"] for f in r], ["a"])
        self.assertEqual((r[0]["country"], r[0]["competition"]), ("usa", "nba"))
        self.assertEqual(R.nombre_fichero(date(2026, 11, 16)), "RESULTS_YESTERDAY_20261116.csv")
