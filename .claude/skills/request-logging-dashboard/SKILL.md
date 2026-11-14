---
name: request-logging-dashboard
description: Add a structured access-log line for every HTTP request plus a Grafana panel/dashboard that lists them all, reusable across projects (Spring Boot + Loki/Grafana by default, adaptable to other stacks).
---

# request-logging-dashboard

Gives every service a place to see every request that hit it — not just
aggregate metrics (requests/s, latency, error rate), but an actual browsable
log of each individual request: method, path, status, duration, caller.

## When to use this

The project already has metrics (Prometheus/Micrometer or equivalent) but
nobody can answer "what did request X look like" or "show me every 404 in
the last hour" without grepping raw logs by hand.

## Default recipe: Spring Boot + Loki/Grafana

This is the concrete, verified implementation for a Spring Boot app whose
logs already reach Loki (e.g. via Grafana Alloy tailing container stdout, as
set up by the `dockerization`/`observability-grafana` skills). Adapt names
(`crud-base`, package names) to the target project.

### 1. Access-log filter (produces the data)

A single servlet filter, logging one structured JSON line per request to its
own logger name so it can be filtered out of the rest of the application
logs:

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestLoggingFilter extends OncePerRequestFilter {

    private static final Logger ACCESS_LOG = LoggerFactory.getLogger("http.access");
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Override
    protected void doFilterInternal(@NonNull HttpServletRequest request, @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {
        long startedAt = System.currentTimeMillis();
        try {
            filterChain.doFilter(request, response);
        } finally {
            ObjectNode entry = OBJECT_MAPPER.createObjectNode();
            entry.put("type", "http-access");
            entry.put("timestamp", Instant.now().toString());
            entry.put("method", request.getMethod());
            entry.put("path", request.getRequestURI());
            entry.put("query", request.getQueryString());
            entry.put("status", response.getStatus());
            entry.put("durationMs", System.currentTimeMillis() - startedAt);
            entry.put("remoteAddr", request.getRemoteAddr());
            ACCESS_LOG.info(entry.toString());
        }
    }
}
```

Key points:
- `@Order(Ordered.HIGHEST_PRECEDENCE)` so it wraps the whole chain, including
  requests that fail validation or get rejected downstream.
- The `"type":"http-access"` field is the anchor a Loki line filter matches
  on — it must be present verbatim so the dashboard query below finds it.
- No new log-shipping config needed if the app's stdout already reaches
  Loki; this is just another log line through the existing pipeline.
- Don't log request/response bodies here (PII/secret risk) — this is an
  access log, not a full HTTP evidence capture (that's a separate concern,
  see the `allure-cucumber-reporting` skill for masked HTTP evidence in
  tests).

### 2. Grafana panel (makes the data visible)

Add a `logs`-type panel to the project's dashboard JSON (or a new dashboard
if none exists yet), pointed at the Loki datasource, filtering on that same
marker field:

```json
{
  "id": <next-free-id>,
  "title": "HTTP access log (all requests)",
  "type": "logs",
  "gridPos": { "x": 0, "y": <below-existing-panels>, "w": 24, "h": 12 },
  "datasource": { "type": "loki", "uid": "loki" },
  "options": { "showTime": true, "sortOrder": "Descending", "wrapLogMessage": true },
  "targets": [
    {
      "expr": "{container=\"<container-name>\"} |= \"\\\"type\\\":\\\"http-access\\\"\"",
      "datasource": { "type": "loki", "uid": "loki" }
    }
  ]
}
```

Replace `<container-name>` with the actual `container` label value (check
via `curl http://localhost:3100/loki/api/v1/label/container/values`, don't
assume it matches the compose service name).

### 3. Verify — don't just claim it works

1. Rebuild and restart the app container so the filter is actually running.
2. Generate a few real requests against the live app.
3. Confirm the raw log line exists: `docker logs <container> | grep http-access`.
4. Confirm Loki actually indexed it — query Loki directly:
   `{container="<name>"} |= `"type":"http-access"`` (backtick raw string
   avoids quoting headaches on the command line) via
   `/loki/api/v1/query_range`, and check `totalEntriesReturned > 0`.
5. Confirm Grafana's own datasource proxy resolves the exact panel query
   (`/api/datasources/proxy/uid/loki/loki/api/v1/query_range`) with the
   double-quote-escaped expression as it appears in the dashboard JSON — the
   raw-Loki test and the dashboard-JSON-escaped test are not automatically
   equivalent; check both.
6. If dashboards are provisioned from a file directory, either wait for the
   provisioning poll interval or recreate the Grafana container so the new
   panel is picked up immediately.

## Adapting to other stacks

The pattern is stack-agnostic: **emit one structured, greppable log line per
request with a stable marker field, then point whatever log-aggregation
dashboard the project already has at that marker.**

- **Node/Express**: a small `morgan`/custom middleware emitting the same
  JSON shape to stdout; same Loki query pattern if logs are shipped the same
  way.
- **No Loki/Grafana at all**: if the project only has Prometheus, this skill
  doesn't apply as-is — a per-request *log* needs a log aggregator, not a
  metrics store. Either add Loki (see `observability-grafana`) or fall back
  to a simple `tail -f` / cloud log-viewer as the "dashboard".
- **Different reverse proxy / gateway already logs access**: if nginx,
  Envoy, etc. already produce a structured access log ahead of the app,
  prefer wiring the dashboard to that instead of duplicating it in the app.

## Ground rules (inherited from how this pattern was built and verified)

- Verify against real running containers and real Loki/Grafana API
  responses — a panel that "should" work because the JSON looks right is not
  verified.
- Don't log request/response bodies in the access-log line; that's a
  separate, explicitly-masked concern if ever needed.
- Never commit/push as part of running this skill unless explicitly asked.
