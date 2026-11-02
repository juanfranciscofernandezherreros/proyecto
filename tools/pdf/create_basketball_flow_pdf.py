from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from proyecto_config import path  # noqa: E402
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether

OUT = path("WORKSPACE") / "outputs" / "pdf" / "flujo_operativo_basketball.pdf"
OUT.parent.mkdir(parents=True, exist_ok=True)

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="TitleFlow", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=22, leading=27, textColor=colors.HexColor("#17324D"), alignment=TA_CENTER, spaceAfter=14))
styles.add(ParagraphStyle(name="SectionFlow", parent=styles["Heading2"], fontName="Helvetica-Bold", fontSize=14, leading=18, textColor=colors.HexColor("#0B6E69"), spaceBefore=10, spaceAfter=7))
styles.add(ParagraphStyle(name="BodyFlow", parent=styles["BodyText"], fontName="Helvetica", fontSize=9.4, leading=13, spaceAfter=5))
styles.add(ParagraphStyle(name="CodeFlow", parent=styles["BodyText"], fontName="Courier", fontSize=8.2, leading=11, backColor=colors.HexColor("#F1F5F8"), borderColor=colors.HexColor("#D5E0E8"), borderWidth=.5, borderPadding=7, spaceBefore=5, spaceAfter=9))

def p(text, style="BodyFlow"):
    return Paragraph(text, styles[style])

def box(text, color="E8F4F3"):
    table = Table([[p(text, "BodyFlow")]], colWidths=[16.5*cm])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), colors.HexColor("#" + color)),
        ("BOX", (0,0), (-1,-1), .7, colors.HexColor("#80AAA8")),
        ("LEFTPADDING", (0,0), (-1,-1), 10), ("RIGHTPADDING", (0,0), (-1,-1), 10),
        ("TOPPADDING", (0,0), (-1,-1), 8), ("BOTTOMPADDING", (0,0), (-1,-1), 8),
    ]))
    return table

def flow(items):
    data = []
    for index, item in enumerate(items):
        data.append([p(item, "BodyFlow")])
        if index < len(items)-1:
            data.append([Paragraph("&#8595;", ParagraphStyle("Arrow", parent=styles["BodyFlow"], alignment=TA_CENTER, fontSize=16, leading=16, textColor=colors.HexColor("#0B6E69")))])
    table = Table(data, colWidths=[16.5*cm])
    commands=[]
    for row in range(0, len(data), 2):
        commands += [("BACKGROUND", (0,row), (-1,row), colors.HexColor("#F1F7F7")), ("BOX", (0,row), (-1,row), .6, colors.HexColor("#9CC8C5")), ("LEFTPADDING", (0,row), (-1,row), 9), ("RIGHTPADDING", (0,row), (-1,row), 9), ("TOPPADDING", (0,row), (-1,row), 6), ("BOTTOMPADDING", (0,row), (-1,row), 6)]
    table.setStyle(TableStyle(commands))
    return table

story = [p("Flujo operativo de Basketball", "TitleFlow"), p("Extraccion, importacion, auditoria y recuperacion continua", "BodyFlow"), Spacer(1, 5)]
story += [p("Vision general", "SectionFlow"), flow([
    "<b>Flashscore</b>: calendario, resultados y datos detallados por partido.",
    "<b>CSV crudos</b>: se guardan por partido en C:\\data\\basketball\\competitions\\&lt;pais&gt;\\&lt;liga&gt;.",
    "<b>Consolidacion aislada</b>: solo el match_id seleccionado pasa a basketball-ready\\current\\&lt;match_id&gt;.",
    "<b>csv-batch-launcher</b>: encola e importa cada CSV a PostgreSQL en el orden correcto.",
    "<b>PostgreSQL, projector, MongoDB, API y web</b>: datos persistidos y publicados.",
    "<b>Auditoria</b>: detecta fixtures finalizados que aun tienen datasets pendientes."
]), Spacer(1, 10)]
story += [box("<b>Regla esencial de URLs:</b> match_id -&gt; resolvedor en navegador -&gt; URL canonica devuelta por Flashscore -&gt; extraccion. Nunca se fabrican URLs con slugs, equipos o plantillas.", "FFF3D9"), PageBreak()]

story += [p("Modulos y BAT principales", "SectionFlow")]
table_data = [[p("Componente", "BodyFlow"), p("Funcion", "BodyFlow")],
    [p("INICIAR_SERVICIOS.bat"), p("Inicia antibloqueo, watcher, Docker, PostgreSQL, MongoDB, projector, API y web.")],
    [p("EJECUTAR_FIXTURES.bat"), p("Extrae e importa solo el calendario de las ligas del catalogo.")],
    [p("EJECUTAR_LIGAS.bat"), p("Procesa RESULTS y, cuando se solicita, POINT_BY_POINT, TEAM_STATS y PLAYER_STATS.")],
    [p("EJECUTAR_AUDITORIA_FIXTURES.bat"), p("Genera auditoria global y una lista de match_id pendientes.")],
    [p("PROCESAR_MATCHIDS_PENDIENTES.bat"), p("Lee la lista de pendientes y procesa exclusivamente esos match_id.")],
    [p("fixtures-processing-audit"), p("Modulo Java independiente que compara fixtures con todas las tablas de datos.")],
    [p("csv-batch-launcher"), p("Cola PostgreSQL que ejecuta los batches e informa COMPLETED o FAILED.")],
]
t = Table(table_data, colWidths=[5.1*cm, 11.4*cm], repeatRows=1)
t.setStyle(TableStyle([("BACKGROUND", (0,0), (-1,0), colors.HexColor("#17324D")), ("TEXTCOLOR", (0,0), (-1,0), colors.white), ("GRID", (0,0), (-1,-1), .35, colors.HexColor("#C7D5DD")), ("VALIGN", (0,0), (-1,-1), "TOP"), ("BACKGROUND", (0,1), (-1,-1), colors.white), ("LEFTPADDING", (0,0), (-1,-1), 7), ("RIGHTPADDING", (0,0), (-1,-1), 7), ("TOPPADDING", (0,0), (-1,-1), 6), ("BOTTOMPADDING", (0,0), (-1,-1), 6)]))
story += [t, Spacer(1,10), p("Procesamiento de un match_id", "SectionFlow"), flow([
    "El BAT lee country, competition, match_id y pending_datasets desde el CSV de auditoria.",
    "El resolvedor de navegador obtiene la URL canonica de Flashscore y valida que el parametro mid coincida.",
    "run_match_pipeline.py extrae el bundle del partido y conserva los CSV crudos.",
    "consolidate_csv.py prepara una carpeta de staging exclusiva para ese match_id.",
    "run_all_csv_batches.py envia RESULTS, MATCH_SUMMARY, TEAM_STATS, PLAYER_STATS y POINT_BY_POINT al launcher.",
    "El launcher espera la confirmacion de PostgreSQL antes de considerar la etapa completada."
]), PageBreak()]

story += [p("Auditoria y ciclo 24/7", "SectionFlow"), flow([
    "Fixtures importados: identifican los partidos existentes y su fecha programada.",
    "Auditoria: solo considera exigibles los partidos cuya fecha de calendario en Europe/Madrid sea anterior a hoy; nunca incluye los de hoy por su hora.",
    "CSV de pendientes: incluye match_id, equipos, liga y datasets que faltan.",
    "Proceso en lotes: el BAT atiende N match_id, registra log y estado por partido, y continua tras errores individuales.",
    "Auditoria final: los partidos completos desaparecen de la cola; los fallidos o no publicados permanecen para reintento."
]), Spacer(1,8), p("Para operar de forma continua, el Programador de tareas de Windows puede lanzar el runtime al iniciar Windows, la actualizacion de fixtures de forma periodica, la auditoria cada 30-60 minutos y el procesamiento en lotes. Debe configurarse para no iniciar una segunda instancia cuando una anterior siga activa.", "BodyFlow"),
box("<b>Resiliencia:</b> un error de partido o dataset se registra en los informes del orquestador y no detiene el resto de ligas. Los CSV vacios se reintentan hasta tres veces; si Flashscore no publica el dato, se conserva el CSV y se deja pendiente.", "FFF3D9"), Spacer(1, 9)]
story += [p("Orden de datos", "SectionFlow"), p("RESULTS -&gt; POINT_BY_POINT -&gt; TEAM_STATS -&gt; PLAYER_STATS. El launcher preserva su propio orden de importacion: RESULTS, FIXTURES, SCORE_SUMMARY, STATS_ALL_PERIODS, PLAYER_STATS y POINT_BY_POINT.", "CodeFlow")]

def footer(canvas, doc):
    canvas.saveState(); canvas.setFont("Helvetica", 8); canvas.setFillColor(colors.HexColor("#607784")); canvas.drawString(1.6*cm, 1.1*cm, "Basketball - flujo operativo"); canvas.drawRightString(A4[0]-1.6*cm, 1.1*cm, f"Pagina {doc.page}"); canvas.restoreState()

doc = SimpleDocTemplate(str(OUT), pagesize=A4, rightMargin=1.6*cm, leftMargin=1.6*cm, topMargin=1.45*cm, bottomMargin=1.7*cm)
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print(OUT)
