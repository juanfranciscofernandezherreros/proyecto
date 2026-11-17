---
name: resultados-ayer-y-pendientes
description: Ciclo de ayer completo sin preguntar nada — primero los resultados de ayer de todas las ligas hasta el projector (basket resultados-ayer, que termina sin extraer si ya están todos en Mongo) y, después, siempre, los partidos pendientes (basket pendientes, que antes hace datos-ayer) con su jugada a jugada y estadísticas. Usar cuando el usuario pida los resultados de ayer y los pendientes, "resultados y luego pendientes", "ponerse al día de ayer" o el ciclo de ayer completo. Solo resultados de ayer: resultados-ayer. Solo pendientes: procesar-pendientes.
---

# Resultados de ayer y después pendientes

Sin preguntar nada al usuario. Antes, comprobar que no hay otro `resultados-ayer` ni
`pendientes` en marcha (dos a la vez se pisan). Lanzar cada paso en segundo plano,
redirigiendo la salida a un fichero del directorio temporal de la sesión, y esperar a
que termine el primero antes del segundo.

## 1. Resultados de ayer

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd resultados-ayer"
```

Lo que hace y cómo leer su salida: skill `resultados-ayer`. Si sale
`Ya estan todos los partidos ...` no extrae nada, y está bien.

## 2. Pendientes (siempre, aunque el paso 1 no extrajera nada o terminara con código 1)

```bash
cmd //c "C:\Develop\basketball\1_EJECUTAR\basket.cmd pendientes"
```

Hace antes `datos-ayer` y luego extrae e importa lo que falta (resumen, jugada a
jugada, estadísticas de equipo y de jugadores). Detalle y tabla de fallos: skill
`procesar-pendientes`.

Los dos pasos se ven en vivo en el dashboard `basket-logs` de Grafana
(http://localhost:8084/d/basket-logs/basketball-logs-de-basket?orgId=1&from=now-3h&to=now&timezone=browser&var-comando=$__all&var-ejecucion=$__all&var-buscar=&refresh=5s).

## Qué decir al terminar

- **Resultados:** "ya estaban todos (n partidos)" o el total extraído y la línea
  `En Mongo (projector): n de m con su marcador`.
- **Pendientes:** cuántos partidos se procesaron, cuántos quedan y por qué, y la ruta
  del CSV de resumen.
- El código de salida de cada paso; si alguno falló, qué hacer según la skill de ese paso.
