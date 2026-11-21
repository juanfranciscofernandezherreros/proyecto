# Revisión del pronóstico de la Euroliga, jornada 12 (publicado el 15/11/2026)

> **Fecha:** 2026-11-21 · **Pronóstico revisado:** `euroliga-jornada-12-2026-11-15` (Mongo,
> `prediction_articles`). **Resultados:** `sql\consultas\2026-11-21_1200_euroliga-jornadas-12-y-13.sql`.
> **Siguiente jornada:** `euroliga-jornada-14-2026-11-24` (publicado hoy).

## Qué pasó: 6 aciertos de 10

| Partido | Pronóstico | Resultado | |
|---|---|---|---|
| Dubai – Anadolu Efes | Dubai 63,3 % (+4,9) | 80-75 (+5) | ✅ |
| Maccabi – Olympiacos | Olympiacos 82,4 % (+13,9) | 95-97 en prórroga (+2) | ✅ (por poco) |
| Fenerbahce – Lyon | Fenerbahce 71,4 % (+8,2) | 115-81 (+34) | ✅ |
| Zalgiris – Bayern | Zalgiris 89,0 % (+18,8) | 117-114 en prórroga (+3) | ✅ (por poco) |
| Baskonia – Hapoel | Hapoel 81,7 % (+13,5) | 82-85 (+3) | ✅ (por poco) |
| Barcelona – Paris | Barcelona 68,5 % (+7,0) | 86-89 | ❌ |
| Olimpia Milano – Crvena Zvezda | Crvena Zvezda 77,0 % (+10,9) | 91-77 (Milano +14) | ❌ |
| Partizan – Valencia | Valencia 56,8 % (+2,5) | 64-76 (Valencia +12) | ✅ |
| Virtus – Panathinaikos | Panathinaikos 74,1 % (+9,5) | 84-79 (Virtus +5) | ❌ |
| Besiktas – Real Madrid | Real Madrid 77,8 % (+11,3) | 83-79 (Besiktas +4) | ❌ |

- **Probabilidad esperada de aciertos:** sumando las diez probabilidades salen 7,4 aciertos; salieron 6.
  Fallar uno o dos más de lo esperado en diez partidos es normal; no demuestra por sí solo que el modelo esté roto.
- **Error del margen:** 13,8 puntos de media (el artículo decía ≈ 10 en el contraste histórico). Los peores:
  Fenerbahce–Lyon (+25,8 más de lo previsto), Olimpia Milano–Crvena Zvezda (24,9) y Zalgiris–Bayern (15,8).
- **Por confianza:** alta, 3 de 5 (fallaron Crvena Zvezda y Real Madrid); media, 2 de 4 (Barcelona y
  Panathinaikos); baja, 1 de 1. El histórico del artículo era 14/19, 18/28 y 6/13.

## Por qué falló

1. **Tres de los cuatro fallos eran favoritos visitantes** (Crvena Zvezda, Panathinaikos y Real Madrid), con
   probabilidades de 74 a 78 %. Los favoritos locales acertaron 3 de 4; los visitantes, 3 de 6. El propio
   artículo avisaba de que seis de los diez favoritos eran visitantes «porque los equipos en peor forma
   juegan en casa». El modelo suma solo 2,5 puntos de localía, y la ventaja de campo real de la Euroliga en
   nuestros datos es mayor: el local gana el 55-56 % y el margen medio del local es +3,1 antes del 1/11 y
   +4,2 desde el 1/11 (consulta PASO 2). Esa diferencia por sí sola no explica 4 fallos, pero va en la
   dirección de los errores.
2. **Se confió en equipos en mala racha, que a veces rompen la racha.** Olimpia Milano llevaba nueve derrotas
   seguidas y ganó por 14; Virtus llevaba cinco y ganó por 5. El modelo mide diferenciales de 13 partidos
   y los de los últimos cinco: una mala racha larga pesa mucho en la previsión y no avisa de que un equipo
   así puede ganar un partido concreto.
3. **Probabilidades demasiado altas para lo que mide el modelo.** Las probabilidades no están calibradas
   (lo dice la metodología). Zalgiris al 89 % ganó en prórroga por 3; Baskonia–Hapoel (81,7 %) se decidió por 3.
   Cuando el margen real fue pequeño en partidos de favorito alto, bastó un mal día para perder.
4. **La segunda opinión (pista) no habría salvado la jornada.** La comparación por pista eligió al mismo
   ganador en nueve de diez: habría fallado los mismos cuatro y, además, Partizan–Valencia (eligió a Partizan por 0,4
   y Valencia ganó por 12), es decir, 5 aciertos de 10. Sí recortó bien los márgenes de los favoritos que ganaron por poco (Olympiacos, Zalgiris, Hapoel).
5. **Lo que el modelo no sabe.** No incluye lesiones, rotaciones ni actuaciones puntuales. En Besiktas–Real
   Madrid, según la prensa, DaQuan Jeffries hizo 20 puntos, su mejor partido de la temporada, y Besiktas
   empezó con un parcial de 16-0 mientras Real Madrid solo lideró en el 2-0 inicial. Eso es ruido que ningún
   modelo de diferenciales puede prever.

## Qué se ha hecho en el pronóstico de la jornada 14

- El modelo y las cifras no se han tocado (misma metodología); lo que cambia es **cómo se cuenta**:
  la introducción avisa del 6/10 de la jornada 12, de que tres de los fallos eran favoritos visitantes y de
  que los tres favoritos visitantes de la jornada 14 son los que la comparación por pista discute.
- Cada análisis señala el dato que matiza la cifra (por ejemplo, Efes fuera lleva 1-5 con −9,2 aunque el
  modelo le da el 81,4 %; Crvena Zvezda ya falló como favorita con el 77 % en la jornada 12).
- Calendario contrastado con la web (24 y 25 de noviembre, mismos emparejamientos).

## Propuestas pendientes (no hechas)

- [ ] Calibrar la **localía** con los datos (hoy fija en 2,5 puntos; el margen medio real del local es 3-4)
      y comprobar si mejora el contraste sobre los 80 partidos ya jugados.
- [ ] **Recortar la probabilidad** de los favoritos visitantes o de los que dependen de la racha, o mostrar
      un rango en lugar de un porcentaje único.
- [ ] Guardar cada previa con su **revisión** (ya existe `euroliga-jornada-8-…-review` en `prediction_articles`),
      para ir midiendo si el modelo mejora jornada a jornada.

## Resultados de la jornada 13 (19 y 20/11, sin pronóstico publicado)

Dubai ganó 74-80 en Maccabi; Panathinaikos 72-87 en Zalgiris; Bayern 100-81 a Baskonia; Olimpia Milano 78-70
a Fenerbahce; Paris 97-96 a Hapoel; Valencia 92-87 a Virtus; Anadolu Efes 107-81 a Lyon; Olympiacos 92-76 al
Real Madrid; Crvena Zvezda ganó 100-103 en Barcelona (prórroga) y Partizan 91-87 a Besiktas (prórroga).
Hubo tres victorias visitantes de diez; las dos prórrogas fueron en la última noche (20/11).

## Fuentes

- Datos: Postgres (`results.results`) y Mongo (`prediction_articles`).
- Eurohoops, crónica Besiktas–Real Madrid: https://www.eurohoops.net/en/euroleague/2037248/besiktas-upsets-real-madrid-after-drama-in-istanbul/
- Calendario de la jornada 14 contrastado en Sportschau (clasificaciones de la 14.ª jornada 2026-27).
