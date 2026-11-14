---
name: observability-grafana
description: Stand up a local Docker-based observability stack (Grafana, Prometheus, Loki, Alloy) with Micrometer/Actuator metrics from the app.
---

# Grafana, Prometheus and Loki Observability Instructions

## Objective

The project must provide a local Docker-based observability stack using:

- Grafana for dashboards and exploration.
- Prometheus for metrics.
- Loki for logs.
- Grafana Alloy or another supported log collector for forwarding container/application logs to Loki.

Spring Boot must expose application metrics through Micrometer and Actuator.

The complete observability stack must be reproducible with Docker Compose.

These instructions must be followed together with all other project instruction files.

All dashboards, labels, metric descriptions, log messages, configuration comments, documentation, and alert names must be written in English.

---

## 1. Observability Architecture

Use the following logical flow:

```text
Spring Boot Application
    ├── /actuator/prometheus ──> Prometheus ──> Grafana
    │
    └── stdout/stderr logs ──> Alloy / log collector ──> Loki ──> Grafana
```

Grafana must use Prometheus and Loki as provisioned data sources.

---

## 2. Required Spring Dependencies

Add Spring Boot Actuator.

Add Micrometer Prometheus registry.

Typical Maven dependencies:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>

<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

Use versions managed by the Spring Boot dependency management whenever possible.

---

## 3. Actuator Configuration

Expose the minimum required endpoints.

Typical configuration:

```properties
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.health.probes.enabled=true
management.metrics.tags.application=${spring.application.name}
```

Use YAML if the project standard is YAML.

Do not expose sensitive actuator endpoints unnecessarily.

---

## 4. Metrics Endpoint

Prometheus must scrape:

```text
/actuator/prometheus
```

The endpoint must return HTTP 200 from the Prometheus network context.

Prometheus must not scrape `localhost` when the Spring Boot app runs in another container.

Use the Docker service name, for example:

```text
app:8080
```

---

## 5. Prometheus Configuration

Create a Prometheus configuration file such as:

```text
observability/prometheus/prometheus.yml
```

Example:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "spring-boot-app"
    metrics_path: /actuator/prometheus
    static_configs:
      - targets:
          - "app:8080"
```

Adapt service names and ports to the actual Compose stack.

---

## 6. Useful Application Metrics

Ensure common Spring Boot/Micrometer metrics are available, including where supported:

```text
http.server.requests
jvm.memory.used
jvm.memory.max
jvm.gc.pause
jvm.threads.live
process.cpu.usage
system.cpu.usage
process.uptime
hikaricp.connections.active
hikaricp.connections.pending
```

Database pool metrics apply only when a supported pool is used.

---

## 7. Custom Business Metrics

Add custom metrics only when they provide operational value.

Examples:

```text
results.creations
results.deletions
results.processing.duration
external.api.failures
```

Use Micrometer:

- `Counter`
- `Timer`
- `Gauge`
- `DistributionSummary`

**Naming pitfall (confirmed, not hypothetical):** never name a counter so
that the dot-to-underscore-converted name ends in `_created` — e.g.
`results.created` becomes `results_created`, and Prometheus/OpenMetrics
reserves the `_created` suffix for its own creation-timestamp series. The
Prometheus registry silently drops the meaningful part and exposes the
counter as the ambiguous bare `results_total` instead of
`results_created_total`, indistinguishable from "total results". Use a verb
form that doesn't collide, e.g. `results.creations` → `results_creations_total`.
After adding any counter, always check its actual exposed name with
`curl .../actuator/prometheus | grep <name>` before wiring a dashboard panel
to it — don't assume the Java name survives unchanged.

Do not create high-cardinality tags.

Avoid tags containing:

- user IDs
- request IDs as metric labels
- email addresses
- arbitrary URLs
- match IDs with unbounded cardinality
- stack traces

---

## 8. Prometheus Labels

Use stable low-cardinality labels.

Good examples:

```text
application
environment
method
status
uri-template
exception
```

Avoid unbounded values.

---

## 9. Application Logging

Application logs should go to stdout/stderr.

Use structured logging when practical.

At minimum logs should clearly include:

- timestamp
- log level
- logger/class
- message

Where tracing/correlation exists, include a correlation or trace identifier.

Do not log passwords, access tokens, API keys, Authorization headers, or sensitive personal data.

---

## 10. Loki

Run Loki as a Docker service.

Create configuration under:

```text
observability/loki/
```

For local development, configure local filesystem storage or another appropriate non-production backend.

Persist Loki data with a named Docker volume when desired.

Do not present a local single-node Loki configuration as production-ready.

---

## 11. Log Collector

Prefer Grafana Alloy for new observability setups when compatible with the environment.

Configure the collector to read Docker/application logs and forward them to Loki.

Alternative collectors may be used when project requirements dictate them.

The collector must add useful stable labels such as:

```text
service
container
environment
```

Avoid using unbounded application data as Loki labels.

---

## 12. Docker Socket Security

If log collection requires Docker metadata through the Docker socket, use read-only access where possible.

Example:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

Document the security implications.

Do not mount the Docker socket into the Spring Boot application or unrelated containers.

---

## 13. Grafana

Run Grafana as part of Docker Compose.

Provision data sources automatically.

Expected data sources:

```text
Prometheus
Loki
```

Do not require a developer to configure data sources manually after every fresh startup.

---

## 14. Grafana Provisioning

Store provisioning files in the repository.

Recommended structure:

```text
observability/
├── prometheus/
│   └── prometheus.yml
├── loki/
│   └── loki-config.yml
├── alloy/
│   └── config.alloy
└── grafana/
    ├── provisioning/
    │   ├── datasources/
    │   │   └── datasources.yml
    │   └── dashboards/
    │       └── dashboards.yml
    └── dashboards/
        └── spring-boot-overview.json
```

---

## 15. Grafana Credentials

Do not hardcode real Grafana admin credentials in committed configuration.

Use environment variables.

Provide safe placeholders in `.env.example`.

Example:

```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=change-me
```

Local defaults may be documented, but production secrets must come from secure secret management.

---

## 16. Grafana Dashboard

Provision at least one useful application dashboard.

The dashboard should include, where available:

- Requests per second.
- HTTP response status distribution.
- Request latency (p95).
- Error rate.
- **Most requested endpoints, ranked** — a table panel using
  `topk(10, sum by (method, uri) (increase(http_server_requests_seconds_count{application="..."}[$__range])))`,
  format `table`, `instant: true`; sort the table panel by the value column
  descending. This answers "what's actually hammering the API" at a glance,
  which a plain requests/s timeseries doesn't.
- Business metric rate(s) and running totals, if custom counters exist (see
  §7) — e.g. creations/deletions rate plus a "net" stat panel.
- JVM heap usage, JVM non-heap usage, CPU usage, live thread count, GC
  activity, application uptime.
- Database connection pool usage: active/idle/pending as a timeseries, plus
  a **utilization gauge** (`sum(hikaricp_connections_active{...}) /
  sum(hikaricp_connections_max{...})`, unit `percentunit`, thresholds around
  0.7/0.9) — a raw active-connection count means nothing without the
  configured max next to it.
- A browsable HTTP access log panel (`type: logs`, Loki datasource) if the
  `request-logging-dashboard` skill's access-log filter is present — see
  that skill for the log line format and exact panel query.

**Organize panels into rows** (Grafana `type: "row"` panels, `collapsed:
false`, used as section dividers) once the dashboard exceeds ~6 panels —
e.g. "Traffic & errors", "Business metrics", "JVM & runtime", "Database
connection pool", "Logs". An unstructured wall of panels stops being
readable well before 15 of them.

Do not create decorative panels that provide no operational value.

---

## 17. Log Dashboard / Explore

Grafana must allow developers to inspect Loki logs.

Provide useful example LogQL queries in README.

Examples conceptually:

```text
{service="app"}
{service="app"} |= "ERROR"
```

Use the actual labels generated by the log collector.

---

## 18. Metrics Queries

Document useful PromQL examples.

Examples conceptually:

```promql
rate(http_server_requests_seconds_count[5m])
```

```promql
sum by (status) (rate(http_server_requests_seconds_count[5m]))
```

Metric names can vary depending on Micrometer/Prometheus naming conventions; verify them against the running application.

---

## 19. Correlation

When practical, make logs and metrics easy to correlate by:

- consistent service name
- environment label/tag
- request path templates
- trace/correlation IDs in logs

Do not put trace IDs into Prometheus metric labels.

---

## 20. Health Monitoring

Prometheus should scrape metrics only from a healthy/reachable application.

Docker health checks should use:

```text
/actuator/health
```

where appropriate.

Grafana itself should not be treated as the application's health check.

---

## 21. Docker Compose Services

When observability is enabled, Compose should include services equivalent to:

```text
app
prometheus
loki
alloy
grafana
```

If a database is required:

```text
database
```

Use a common Docker network.

Only expose host ports that developers need.

---

## 22. Typical Local Ports

Ports may be configurable, but common local defaults are:

```text
Application: 8080
Prometheus: 9090
Loki: 3100
Grafana: 3000
```

Internal infrastructure ports do not all need host exposure.

---

## 23. Persistence

Use named volumes where useful:

```text
prometheus_data
loki_data
grafana_data
```

Document how to reset them.

Warn that:

```bash
docker compose down -v
```

deletes local persisted observability data.

---

## 24. Grafana Data Source Provisioning

Provision Prometheus using the Docker service URL:

```text
http://prometheus:9090
```

Provision Loki using:

```text
http://loki:3100
```

Do not use `localhost` between containers.

---

## 25. Automated Verification

After starting the stack, verify:

1. Application health endpoint returns HTTP 200.
2. Application Prometheus endpoint returns HTTP 200.
3. Prometheus target for the application is UP.
4. Loki is reachable from Grafana.
5. Grafana has Prometheus data source.
6. Grafana has Loki data source.
7. Application metrics appear in Prometheus.
8. Application logs appear in Loki.
9. Provisioned dashboard loads.
10. No secrets appear in logs.
11. Every panel's own query — run through Grafana's datasource proxy
    (`/api/datasources/proxy/uid/<uid>/api/v1/query...`), not just raw
    Prometheus/Loki — returns a non-empty result. A query that works
    against Prometheus directly can still fail inside the dashboard if the
    datasource `uid` or a template variable like `$__range` doesn't resolve
    the way the panel assumes.

---

## 26. Prometheus Target Verification

The agent must inspect or query Prometheus and confirm the application target is:

```text
UP
```

Do not consider the metrics integration complete merely because containers are running.

---

## 27. Loki Verification

Generate at least one known application log event and verify it can be queried through Loki/Grafana.

The log pipeline is incomplete until logs are actually visible.

---

## 28. Traffic Generation for Verification

Generate a small amount of safe test traffic against the API after startup.

For example:

```text
GET health
GET collection endpoint
one successful API call
one controlled 4xx request
```

Then verify metrics and logs reflect this traffic.

Do not mutate important data merely for observability verification.

---

## 29. Cucumber and Observability

Cucumber tests remain functional independently of Grafana.

Observability should not be required for unit tests.

When running the full Docker stack, Cucumber/API traffic may be used to populate local metrics and logs for demonstration.

---

## 30. Alerts

Alerts are optional unless explicitly requested.

If alerts are added, useful examples include:

- application target down
- elevated 5xx rate
- unusually high latency
- JVM memory pressure

Do not create noisy alerts without meaningful thresholds.

---

## 31. README Integration

Add an Observability section documenting:

- How to start the stack.
- Grafana URL.
- Prometheus URL when exposed.
- Application metrics endpoint.
- Default/local credentials policy.
- How to view logs.
- Useful PromQL queries.
- Useful LogQL queries.
- Dashboard name.
- How to reset observability volumes.

---

## 32. Security

Observability configuration must:

- Never expose secrets in metrics.
- Never log passwords or tokens.
- Avoid sensitive high-cardinality labels.
- Avoid public exposure of internal metrics in production.
- Protect Grafana appropriately outside local development.
- Keep Docker socket access limited to the log collector if required.
- Document that local Compose defaults are not automatically production-ready.

---

## 33. Environment Separation

Support environment-specific configuration where appropriate.

At minimum distinguish local development assumptions from production.

Do not assume a single-node Docker Compose stack is a production deployment architecture.

---

## 34. Required Agent Workflow

When asked to add observability:

1. Read all instruction files.
2. Add Actuator.
3. Add Micrometer Prometheus registry.
4. Configure health and Prometheus endpoints.
5. Verify application metrics locally.
6. Add Prometheus configuration.
7. Add Loki configuration.
8. Add Alloy/log collector configuration.
9. Add Grafana provisioning.
10. Provision Prometheus data source.
11. Provision Loki data source.
12. Create/provision application dashboard.
13. Integrate services into Docker Compose.
14. Configure volumes.
15. Configure environment variables.
16. Build and test the application.
17. Start the complete stack.
18. Verify application health.
19. Verify Prometheus target is UP.
20. Verify metrics exist.
21. Generate a known log message/request.
22. Verify logs are visible in Loki.
23. Verify Grafana dashboard.
24. Update README.
25. Fix all issues before completion.

---

## 35. Completion Criteria

Observability is complete only when:

- Actuator is configured.
- Prometheus metrics endpoint works.
- Prometheus scrapes the app successfully.
- Application target is UP.
- Loki runs.
- Logs are forwarded to Loki.
- Logs can be queried.
- Grafana runs.
- Prometheus is provisioned in Grafana.
- Loki is provisioned in Grafana.
- At least one useful dashboard is provisioned.
- Docker Compose starts the complete local stack.
- Credentials and secrets are externalized.
- No sensitive data is logged.
- README explains how to use the observability stack.

---

## Priority

This file defines metrics, logs, and Grafana observability.

It must remain compatible with Dockerization, API-first development, testing, Swagger/OpenAPI, Lombok/MapStruct, and English-only project conventions.
