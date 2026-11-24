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
from unittest import mock

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


class ReextraerH2hCuotasTests(unittest.TestCase):
    def test_grupo_h2h_cuotas(self):
        ids, nombres, _ = reextraer._argumentos(["--dataset", "h2h-cuotas", "vyf2I8i5"])
        self.assertEqual(ids, ["vyf2I8i5"])
        self.assertEqual(nombres, ["h2h", "cuota-ganador", "cuota-1x2", "cuota-total", "cuota-handicap"])
        # «todo» no incluye H2H ni cuotas (lo usa datos_ayer).
        _, todo, _ = reextraer._argumentos(["vyf2I8i5"])
        self.assertNotIn("h2h", todo)

    def _scraper_falso(self, raiz, contenido):
        """subprocess.run falso: escribe los CSV indicados como haría el bundle."""
        def run(cmd, **_kwargs):
            carpeta = raiz / "m1"
            carpeta.mkdir(exist_ok=True)
            for prefijo, filas in contenido.items():
                cuerpo = "cabecera\n" + "".join("fila\n" for _ in range(filas))
                (carpeta / f"{prefijo}_20261124120000_m1.csv").write_text(cuerpo, encoding="utf-8")
            return mock.Mock(returncode=0, stdout="", stderr="")
        return run

    def test_una_sola_llamada_y_vacio_no_es_fallo(self):
        with tempfile.TemporaryDirectory() as d:
            raiz = Path(d)
            run = self._scraper_falso(raiz, {"H2H": 15, "ODDS_HOME_AWAY": 15, "ODDS_1X2": 0})
            with mock.patch.object(reextraer.subprocess, "run", side_effect=run) as llamado:
                res = reextraer._extraer_juntos(
                    {"PYTHON": "py", "SCRAPER": "fs.py"}, {}, ["h2h", "cuota-ganador", "cuota-1x2"],
                    "m1", "https://x/?mid=m1", raiz)
            self.assertEqual(llamado.call_count, 1)
            cmd = llamado.call_args.args[0]
            self.assertEqual(cmd.count("--dataset"), 3)
            self.assertEqual(res["h2h"].name, "H2H_20261124120000_m1.csv")
            self.assertIsNone(res["cuota-1x2"])  # la NBA no ofrece 1X2

    def test_si_falta_un_csv_reintenta_y_falla_con_lo_conseguido(self):
        with tempfile.TemporaryDirectory() as d:
            raiz = Path(d)
            run = self._scraper_falso(raiz, {"H2H": 5})
            with mock.patch.object(reextraer.subprocess, "run", side_effect=run) as llamado:
                with self.assertRaises(reextraer.Fallo) as error:
                    reextraer._extraer_juntos(
                        {"PYTHON": "py", "SCRAPER": "fs.py"}, {}, ["h2h", "cuota-total"],
                        "m1", "https://x/?mid=m1", raiz)
            self.assertEqual(llamado.call_count, 3)
            self.assertIn("ODDS_OVER_UNDER", str(error.exception.args[0]))
            self.assertEqual(list(error.exception.args[1]), ["h2h"])


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
        self.assertAlmostEqual(self.previa.probabilidad_local(margen), 79.3, places=1)
        self.assertAlmostEqual(self.previa.probabilidad_local(0), 50.0, places=6)

    def test_la_escala_esta_calibrada_en_14(self):
        """Escala 14 (calibrada el 2026-11-21): 10 puntos de margen son un 67 %, no el 75 % de la escala 9,
        y la confianza alta (75 % o mas) exige unos 15 puntos."""
        self.assertEqual(self.previa.ESCALA, 14.0)
        self.assertAlmostEqual(self.previa.probabilidad_local(10.0), 67.1, places=1)
        self.assertLess(self.previa.probabilidad_local(15.0), 75.0)
        self.assertGreaterEqual(self.previa.probabilidad_local(15.4), 75.0)

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
        self.assertEqual(partizan["winnerProbability"], 54.4)  # escala 14 (con la 9 era 56,8)
        self.assertTrue(partizan["prediction"].startswith("2 · Valencia · 1: 45,6% · 2: 54,4%"))

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

    def _observabilidad(self, comando, env=None, marca=None):
        """Ejecuta _asegurar_observabilidad sin Docker ni navegador; devuelve lo abierto."""
        import tempfile
        from unittest import mock
        import basket
        ok = mock.Mock(returncode=0)
        if marca is None:  # marca nueva en cada llamada: la primera vez siempre abre
            marca = Path(tempfile.mkdtemp()) / ".grafana-abierta"
        with mock.patch.object(basket.subprocess, "run", return_value=ok), \
             mock.patch.object(basket.webbrowser, "open") as abrir, \
             mock.patch.object(basket, "marca_grafana", return_value=marca), \
             mock.patch.dict(basket.os.environ, env or {}, clear=False):
            basket.os.environ.pop("BASKET_SIN_GRAFANA", None)
            if not env:
                basket.os.environ.pop("BASKET_NO_ABRIR_GRAFANA", None)
            basket._asegurar_observabilidad(comando, None)
        return abrir

    def test_abre_dashboard_de_logs_por_defecto(self):
        abrir = self._observabilidad("pendientes")
        abrir.assert_called_once()
        self.assertIn("/d/basket-logs/", abrir.call_args[0][0])

    def test_abre_tambien_en_tareas_programadas(self):
        for comando in ("resultados-ayer", "ciclo-diario", "inicio-automatico"):
            self._observabilidad(comando).assert_called_once()

    def test_no_abre_con_variable(self):
        self._observabilidad("pendientes", {"BASKET_NO_ABRIR_GRAFANA": "1"}).assert_not_called()

    def test_una_sola_pestana_aunque_se_lancen_varios_comandos(self):
        import tempfile
        marca = Path(tempfile.mkdtemp()) / ".grafana-abierta"
        self._observabilidad("reextraer", marca=marca).assert_called_once()
        for _ in range(3):  # lotes en paralelo: ya no abren más pestañas
            self._observabilidad("reextraer", marca=marca).assert_not_called()

    def test_vuelve_a_abrir_pasadas_12_horas(self):
        import os
        import tempfile
        marca = Path(tempfile.mkdtemp()) / ".grafana-abierta"
        marca.touch()
        hace_13h = marca.stat().st_mtime - 13 * 3600
        os.utime(marca, (hace_13h, hace_13h))
        self._observabilidad("pendientes", marca=marca).assert_called_once()


class TareaResultadosTests(unittest.TestCase):
    """Tarea «Resultados de ayer por la manana»: diaria, despierta el equipo y lanza resultados-ayer."""

    def _tareas(self):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "arranque"))
        import tareas
        return tareas

    def test_xml_diario_con_despertar(self):
        xml = self._tareas()._xml("resultados", "07:30")
        self.assertIn("<StartBoundary>2026-01-01T07:30:00</StartBoundary>", xml)
        self.assertIn("<WakeToRun>true</WakeToRun>", xml)
        self.assertIn("<StartWhenAvailable>true</StartWhenAvailable>", xml)
        self.assertIn("<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>", xml)
        self.assertIn("basket.cmd\" resultados-ayer</Arguments>", xml)

    def test_hora_por_defecto(self):
        self.assertEqual(self._tareas().POR_DEFECTO["resultados"], "07:30")


class CuriosidadesFeedTests(unittest.TestCase):
    """basket curiosidades: filas de psql -> documentos de curiosity_feed."""

    def _mod(self):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import curiosidades
        return curiosidades

    def test_parsea_y_convierte_en_orden(self):
        c = self._mod()
        us = c.SEPARADOR
        texto = (us.join(["22/11/2026", "2", "lnb", "Lyon 91-101 Bourg", "sorpresa", "Bourg (2-6) ganó", "pnQ"]) + "\n"
                 + us.join(["21/11/2026", "3", "nba", "PHI 132-129 MIL", "40 puntos", "Herro 50", "abc"]) + "\n")
        docs = c.documentos(c.parsear(texto))
        self.assertEqual([d["rank"] for d in docs], [0, 1])
        self.assertEqual(docs[0]["date"], "2026-11-22")
        self.assertEqual(docs[1]["level"], 3)
        self.assertEqual(docs[1]["type"], "40 puntos")
        self.assertEqual(docs[0]["_id"], "00000-pnQ-sorpresa")

    def test_fila_mal_formada_falla(self):
        c = self._mod()
        with self.assertRaises(ValueError):
            c.parsear(c.SEPARADOR.join(["22/11/2026", "2", "lnb"]))

    def test_usa_la_consulta_validada(self):
        self.assertTrue(self._mod().SQL.exists())


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

    def test_encadena_pendientes_salvo_solo_csv_o_variable(self):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import resultados_ayer as R
        self.assertTrue(R.encadenar_pendientes([], {}))
        self.assertTrue(R.encadenar_pendientes(["--forzar"], {}))
        self.assertFalse(R.encadenar_pendientes(["--solo-csv"], {}))
        self.assertFalse(R.encadenar_pendientes([], {"RESULTADOS_AYER_PENDIENTES": "0"}))

    def test_pendientes_avisa_a_telegram_al_empezar(self):
        from unittest import mock
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "pendientes"))
        import procesar_matchids as PM
        self.assertEqual(PM.mensaje_inicio(54), "⏳ Pendientes: 54 partidos por procesar (~54 min).")
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "monitor"))
        import telegram_csv
        with mock.patch.object(telegram_csv, "configurado", return_value=True), \
             mock.patch.object(telegram_csv, "enviar_texto") as enviar:
            PM.avisar_inicio(3)
        enviar.assert_called_once_with(PM.mensaje_inicio(3))
        with mock.patch.object(telegram_csv, "configurado", return_value=True), \
             mock.patch.object(telegram_csv, "enviar_texto", side_effect=OSError("sin red")):
            PM.avisar_inicio(3)  # no debe lanzar

    def test_seguimiento_genera_sql_seguro_y_no_corta_si_falla(self):
        from unittest import mock
        import seguimiento as S
        sql = S.sql_empezar("r1", "europe/euroleague", "europe", "euroleague", "PLAYER_STATS O'Neal")
        self.assertIn("'PLAYER_STATS O''Neal'", sql)
        self.assertIn("'RUNNING') RETURNING id;", sql)
        self.assertIn("estado = 'FAILED'", S.sql_terminar(7, "FAILED", "x"))
        with mock.patch.object(S.subprocess, "run", side_effect=OSError("sin docker")):
            self.assertIsNone(S.empezar({}, "r", "l", "p", "c", "paso"))
        S.terminar({}, None, "COMPLETED")  # sin id no hace nada
        S._activo = True

    def test_motivo_error_salta_el_volcado_de_la_pila(self):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "pendientes"))
        import procesar_matchids as PM
        lineas = ["selenium.common.exceptions.WebDriverException: Message: net::ERR_NAME_NOT_RESOLVED",
                  "Stacktrace:", "(No symbol) [0x7ff87b2d9c5c]"]
        self.assertIn("ERR_NAME_NOT_RESOLVED", PM.motivo_error(lineas))
        self.assertEqual(PM.motivo_error(["sin pistas"]), "sin pistas")
        self.assertEqual(PM.motivo_error([]), "")

    def test_csv_faltan_cruza_disco_e_intentos(self):
        from unittest import mock
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "pendientes"))
        import csv_faltan as CF
        self.assertEqual(CF.datasets_con_csv(["SCORE_SUMMARY_1_x.csv", "PLAYER_STATS_1_x.csv"]),
                         {"MATCH_SUMMARY", "PLAYER_STATS"})
        row = {"match_id": "Gr62XNa6", "country": "europe", "competition": "euroleague",
               "pending_datasets": "POINT_BY_POINT,PLAYER_STATS"}
        with mock.patch.object(CF, "csv_en_disco", return_value=["PLAYER_STATS_1_Gr62XNa6.csv"]):
            f = CF.filas([row], {"Gr62XNa6": ("20261118080204", "ERROR", "ERR_NAME_NOT_RESOLVED")})[0]
        self.assertEqual((f["sin_csv"], f["con_csv_sin_cargar"]), ("POINT_BY_POINT", "PLAYER_STATS"))
        self.assertIn("ERROR: ERR_NAME_NOT_RESOLVED", f["motivo"])
        self.assertTrue(CF.motivo(None).startswith("nunca"))

    def test_pendientes_avisa_de_cada_partido_y_cuantos_quedan(self):
        from unittest import mock
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "pendientes"))
        import procesar_matchids as PM
        row = {"home_team": "Houston Rockets", "away_team": "Golden State Warriors",
               "country": "usa", "competition": "nba"}
        self.assertEqual(PM.mensaje_partido(3, 54, row, "COMPLETED"),
                         "✅ 3/54 · Houston Rockets - Golden State Warriors (usa/nba) · quedan 51")
        self.assertEqual(PM.mensaje_partido(54, 54, row, "ERROR", "sin conexion"),
                         "❌ 54/54 · Houston Rockets - Golden State Warriors (usa/nba) · sin conexion · quedan 0")
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "monitor"))
        import telegram_csv
        with mock.patch.object(telegram_csv, "configurado", return_value=True), \
             mock.patch.object(telegram_csv, "enviar_texto", side_effect=OSError("sin red")):
            PM.avisar_partido(1, 2, row, "COMPLETED")  # no debe lanzar

    def test_main_lanza_pendientes_y_devuelve_el_peor_codigo(self):
        from unittest import mock
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import resultados_ayer as R
        import matchids_pendientes as P
        with mock.patch.object(R, "_ejecutar", return_value=0), \
             mock.patch.object(R, "_avisar"), \
             mock.patch.object(P, "main", return_value=1) as pend, \
             mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("RESULTADOS_AYER_PENDIENTES", None)
            self.assertEqual(R.main([]), 1)
        pend.assert_called_once_with([])


class ResultadosAyerCuadrePrevioTests(unittest.TestCase):
    """resultados-ayer: el cuadre previo decide que ligas extraer."""

    def setUp(self):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import resultados_ayer
        self.R = resultados_ayer
        self.fx = {"a": {"liga": "usa/nba", "local": "X", "visitante": "Y"},
                   "b": {"liga": "israel/winner-league", "local": "Z", "visitante": "W"}}

    def test_todos_en_mongo_no_hay_pendientes(self):
        mg = {"a": {"marcador": (100, 90), "secciones": []},
              "b": {"marcador": (80, 70), "secciones": []}}
        self.assertEqual(self.R.ligas_pendientes(self.fx, {}, mg), (set(), 2))

    def test_falta_en_mongo_o_sin_marcador(self):
        mg = {"a": {"marcador": (None, None), "secciones": []}}
        pend, total = self.R.ligas_pendientes(self.fx, {}, mg)
        self.assertEqual(pend, {"usa/nba", "israel/winner-league"})
        self.assertEqual(total, 2)

    def test_marcador_distinto_al_de_flashscore(self):
        fs = {"a": {"liga": "usa/nba", "local": "X", "visitante": "Y", "marcador": (101, 90)}}
        mg = {"a": {"marcador": (100, 90), "secciones": []},
              "b": {"marcador": (80, 70), "secciones": []}}
        self.assertEqual(self.R.ligas_pendientes(self.fx, fs, mg)[0], {"usa/nba"})


class TelegramCsvTests(unittest.TestCase):
    """Vigilante que avisa por Telegram de cada CSV procesado (monitor/telegram_csv.py)."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "monitor"))
        import telegram_csv
        cls.T = telegram_csv

    def test_aviso_solo_estado_nombre_y_hora_de_madrid(self):
        aviso = self.T.aviso({"status": "COMPLETED", "batch_type": "player-stats", "exit_code": 0,
                              "file_path": r"C:\data\x\8SJueQyq\PLAYER_STATS_1_8SJueQyq.csv",
                              "finished_at": "2026-11-17T11:49:30.123456Z", "error": None})
        self.assertEqual(aviso, "\u2705 COMPLETADO \u00b7 PLAYER_STATS_1_8SJueQyq.csv \u00b7 17/11 12:49:30")

    def test_aviso_fallido_sin_error_ni_mas_datos(self):
        aviso = self.T.aviso({"status": "FAILED", "file_path": r"C:\x\R.csv",
                              "finished_at": "2026-07-01T10:00:00Z", "error": "boom", "exit_code": 1})
        self.assertEqual(aviso, "\u274c FALLIDO \u00b7 R.csv \u00b7 01/07 12:00:00")

    def test_configurado_solo_con_token_y_chat(self):
        self.assertFalse(self.T.configurado({"TELEGRAM_BOT_TOKEN": "t", "TELEGRAM_CHAT_ID": ""}))
        self.assertFalse(self.T.configurado({"TELEGRAM_BOT_TOKEN": " ", "TELEGRAM_CHAT_ID": "1"}))
        self.assertTrue(self.T.configurado({"TELEGRAM_BOT_TOKEN": "t", "TELEGRAM_CHAT_ID": "1"}))

    def test_marca_de_agua_con_comilla_se_rechaza(self):
        with self.assertRaises(ValueError):
            self.T.terminados_desde("2026-01-01'; DROP TABLE x; --")

    def test_token_no_esta_en_la_configuracion_versionada(self):
        texto = (RAIZ / "config" / "basketball.env").read_text(encoding="utf-8")
        for linea in texto.splitlines():
            if linea.startswith(("TELEGRAM_BOT_TOKEN=", "TELEGRAM_CHAT_ID=")):
                self.assertEqual(linea.split("=", 1)[1].strip(), "", linea.split("=")[0])

    def test_mensaje_pronostico_solo_prediccion_y_enlace(self):
        articulo = {"title": "Euroliga — Jornada 12", "introduction": "texto largo",
                    "games": [{"homeTeam": "Besiktas", "awayTeam": "Real Madrid", "winner": "Real Madrid",
                               "winnerProbability": 78.4, "startsAt": "2026-11-18T17:00:00Z", "analysis": "x"},
                              {"homeTeam": "Dubai", "awayTeam": "Efes", "winner": "Dubai",
                               "winnerProbability": 63.3, "startsAt": "2026-11-17T16:00:00Z", "analysis": "y"}]}
        msg = self.T.mensaje_pronostico(articulo, "http://localhost:8083/predictions/j12")
        self.assertEqual(msg.splitlines(), [
            "\U0001F3C0 Euroliga — Jornada 12",
            "17/11 17:00  Dubai - Efes → Dubai 63%",
            "18/11 18:00  Besiktas - Real Madrid → Real Madrid 78%",
            "http://localhost:8083/predictions/j12"])
        self.assertNotIn("texto largo", msg)


class ResultadosAyerResumenTests(unittest.TestCase):
    """basket resultados-ayer: una linea RESUMEN al terminar (tambien va al bot)."""

    @classmethod
    def setUpClass(cls):
        from datetime import date
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import resultados_ayer
        cls.R, cls.dia = resultados_ayer, date(2026, 11, 16)

    def test_ya_estaban(self):
        self.assertEqual(self.R.linea_resumen({"dia": self.dia, "ya": True, "total": 8}),
                         "✅ Resultados de ayer 16/11 · ya estaban los 8 en Mongo")

    def test_todos_en_mongo(self):
        r = {"dia": self.dia, "extraidos": 8, "ligas_fallo": 0, "cargados": 8, "en_mongo": 8, "cargas_fallo": 0}
        self.assertEqual(self.R.linea_resumen(r), "✅ Resultados de ayer 16/11 · 8 de 8 en Mongo")

    def test_faltan_en_mongo_y_liga_con_fallo(self):
        r = {"dia": self.dia, "extraidos": 8, "ligas_fallo": 1, "cargados": 8, "en_mongo": 7, "cargas_fallo": 0}
        self.assertEqual(self.R.linea_resumen(r),
                         "❌ Resultados de ayer 16/11 · 7 de 8 en Mongo · 1 liga(s) con fallo")

    def test_error(self):
        self.assertEqual(self.R.linea_resumen({"dia": self.dia, "error": "no se pudieron arrancar los servicios"}),
                         "❌ Resultados de ayer 16/11 · ERROR: no se pudieron arrancar los servicios")

    def test_sin_partidos(self):
        self.assertEqual(self.R.linea_resumen({"dia": self.dia, "extraidos": 0, "ligas_fallo": 0}),
                         "✅ Resultados de ayer 16/11 · ningún partido")


class PendientesResumenTests(unittest.TestCase):
    """basket pendientes: una linea RESUMEN al terminar (tambien va al bot)."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import matchids_pendientes
        cls.P = matchids_pendientes

    def test_todo_bien_aunque_falten_secciones(self):
        r = {"procesados": 42, "errores": 0, "en_mongo": 42, "completos": 27, "quedan": 55}
        self.assertEqual(self.P.linea_resumen(r),
                         "✅ Pendientes · 42 procesados · 42 de 42 en Mongo (27 completos) · quedan 55")

    def test_errores_y_ausentes_son_fallo(self):
        r = {"procesados": 40, "errores": 2, "en_mongo": 39, "completos": 25, "quedan": 57}
        self.assertEqual(self.P.linea_resumen(r),
                         "❌ Pendientes · 40 procesados · 2 con error · 39 de 40 en Mongo (25 completos) · quedan 57")

    def test_nada_que_procesar(self):
        self.assertEqual(self.P.linea_resumen({"procesados": 0, "errores": 0, "quedan": 0}),
                         "✅ Pendientes · nada que procesar · quedan 0")

    def test_error_sin_auditoria(self):
        self.assertEqual(self.P.linea_resumen({"error": "no se pudieron arrancar los servicios", "quedan": None}),
                         "❌ Pendientes · ERROR: no se pudieron arrancar los servicios")


class TokensTests(unittest.TestCase):
    """basket tokens: mide la carga fija (CLAUDE.md, reglas, descripciones) y la de cada skill."""

    def test_mide_fijo_y_salta_las_skills_no_invocables(self):
        sys.path.insert(0, str(RAIZ / "scripts" / "py" / "lanzadores"))
        import tokens as T
        with tempfile.TemporaryDirectory() as d:
            raiz = Path(d)
            (raiz / "CLAUDE.md").write_text("x" * 100, encoding="utf-8")
            (raiz / ".claude" / "rules").mkdir(parents=True)
            (raiz / ".claude" / "rules" / "r.md").write_text("y" * 40, encoding="utf-8")
            (raiz / ".claude" / "rules" / "java.md").write_text(
                '---\npaths:\n  - "**/*.java"\n---\nregla', encoding="utf-8")
            for nombre, extra in (("a", "model: haiku\n"), ("b", "disable-model-invocation: true\n")):
                (raiz / ".claude" / "skills" / nombre).mkdir(parents=True)
                (raiz / ".claude" / "skills" / nombre / "SKILL.md").write_text(
                    f"---\nname: {nombre}\ndescription: {'d' * 20}\n{extra}---\n\ncuerpo\n", encoding="utf-8")
            m = T.medir(raiz)
        self.assertEqual(m["fijo"], [("CLAUDE.md", 100), ("rules/r.md", 40)])
        self.assertEqual([n for n, _ in m["condicional"]], ["rules/java.md"])
        self.assertEqual([(s[0], s[1], s[3]) for s in m["skills"]], [("a", 20, "haiku")])
        self.assertEqual(m["total_fijo"], 160)
        self.assertEqual(T.tokens(160), 40)
