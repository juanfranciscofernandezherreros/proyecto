---
name: dockerization
description: Containerize the project end to end (Dockerfile, .dockerignore, docker-compose.yml) so it builds, tests, and runs consistently in Docker.
---

# Dockerization Instructions

## Objective

The entire project must be containerized so it can be built, tested, started, stopped, and operated consistently with Docker.

These instructions must be followed together with all other project instruction files.

All Docker-related files, comments, service names, environment variable documentation, health checks, and README instructions must be written in English.

---

## 1. Required Deliverables

Create and maintain at minimum:

```text
Dockerfile
.dockerignore
docker-compose.yml
```

When environment-specific overrides are useful, also use:

```text
docker-compose.override.yml
.env.example
```

Never commit real secrets in `.env`.

---

## 2. Multi-Stage Dockerfile

Use a multi-stage Docker build for the Spring Boot application.

Recommended stages:

```text
Maven build stage
    ↓
Runtime JRE stage
```

Example pattern:

```dockerfile
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Adapt Java and Maven versions to the actual project.

---

## 3. Build Tests

The normal CI/build workflow must run tests before producing a releasable image.

Do not use `-DskipTests` as the only project build path.

A valid workflow is:

```bash
mvn clean verify
docker build -t application:local .
```

The Docker image may use a previously validated artifact or run tests inside the build when appropriate.

---

## 4. Non-Root Runtime

The final application container should run as a non-root user whenever practical.

Create or use a dedicated application user.

Avoid running production workloads as root.

---

## 5. Minimal Runtime Image

Use a JRE runtime image rather than a full JDK when compilation is already complete.

Avoid unnecessary packages in the runtime image.

Keep the final image small and reproducible.

---

## 6. Docker Ignore

Create `.dockerignore`.

At minimum exclude:

```text
target/
.git/
.idea/
.vscode/
*.iml
*.log
.env
node_modules/
```

Add project-specific exclusions when appropriate.

---

## 7. Configuration Through Environment Variables

Application runtime configuration must be externalized.

Examples:

```text
SERVER_PORT
SPRING_PROFILES_ACTIVE
SPRING_DATASOURCE_URL
SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_PASSWORD
```

Do not hardcode secrets in:

```text
Dockerfile
docker-compose.yml
application.properties
application.yml
source code
```

---

## 8. Environment Example File

Create:

```text
.env.example
```

It may contain safe placeholders:

```env
APP_PORT=8080
SPRING_PROFILES_ACTIVE=docker
DB_NAME=appdb
DB_USER=app
DB_PASSWORD=change-me
```

Never put actual passwords or tokens in the example file.

---

## 9. Docker Compose

Use Docker Compose to start the complete local stack.

At minimum the compose file should include the application service.

If the project uses an external database, include it as a separate service.

Example architecture:

```text
application
    ↓
database
```

If observability is enabled, Compose may additionally include:

```text
application
prometheus
loki
promtail or grafana-alloy
grafana
```

---

## 10. Service Naming

Use clear English service names.

Preferred:

```text
app
database
prometheus
loki
grafana
alloy
```

Avoid arbitrary names such as:

```text
container1
server2
testx
```

---

## 11. Networks

Create a dedicated Docker network when useful.

Containers must communicate by Docker service name rather than `localhost`.

Example:

```text
http://app:8080
http://prometheus:9090
http://loki:3100
```

Remember that `localhost` inside a container refers to that same container.

---

## 12. Volumes

Use named volumes for stateful components.

Examples:

```text
database_data
grafana_data
prometheus_data
loki_data
```

Do not store persistent production data only in ephemeral container filesystems.

---

## 13. Health Checks

Define meaningful health checks.

For Spring Boot, prefer Spring Boot Actuator health:

```text
/actuator/health
```

A Docker health check should verify actual application readiness where practical.

Do not use a health check that always returns success.

---

## 14. Spring Boot Actuator

If not already present and compatible with project requirements, include Spring Boot Actuator.

Expose only endpoints that are required.

Typical internal operational endpoints:

```text
/actuator/health
/actuator/info
/actuator/prometheus
```

Do not expose sensitive actuator endpoints publicly without security controls.

---

## 15. Dependency Startup

Use Compose health conditions or resilient application retry behavior where dependencies need time to start.

Do not assume that container startup order guarantees application readiness.

---

## 16. Database Profile

When Docker uses a persistent database instead of H2, create a Docker-specific Spring profile where appropriate.

Example:

```text
application-docker.yml
```

Keep test configuration isolated from Docker production-like configuration.

---

## 17. Ports

Make host ports configurable.

Example:

```yaml
ports:
  - "${APP_PORT:-8080}:8080"
```

Avoid unnecessary public port exposure between internal services.

---

## 18. Logging

Application logs should be written to standard output/error by default.

Avoid depending exclusively on log files inside the application container.

This allows Docker and the observability stack to collect logs consistently.

---

## 19. Image Metadata

When appropriate, add OCI labels for:

- application name
- version
- source repository
- description

Do not embed secrets in image metadata.

---

## 20. Image Tagging

Use deterministic image tags where available.

Examples:

```text
application:local
application:1.0.0
application:<git-sha>
```

Do not rely exclusively on `latest` for controlled environments.

---

## 21. Security

The Docker setup must:

- Avoid embedding secrets.
- Run as non-root where possible.
- Use minimal base images.
- Avoid privileged mode.
- Avoid mounting the Docker socket unless explicitly required.
- Avoid unnecessary capabilities.
- Avoid unnecessary host filesystem mounts.
- Keep internal infrastructure ports private when possible.

---

## 22. Docker Compose Commands

README must document commands such as:

```bash
docker compose build
docker compose up -d
docker compose ps
docker compose logs -f app
docker compose down
```

For a full reset when explicitly needed:

```bash
docker compose down -v
```

Warn that `-v` removes named volume data.

---

## 23. Application Verification

After starting the stack:

1. Verify all required containers are running.
2. Verify health checks.
3. Verify the application responds.
4. Verify Swagger UI if enabled.
5. Verify OpenAPI endpoint.
6. Verify database connectivity.
7. Verify observability endpoints if configured.

---

## 24. Testing From Docker

Where practical, provide a reproducible method to run tests in a container or build stage.

The canonical project tests remain:

```bash
mvn clean verify
```

Cucumber and service unit tests must still pass.

---

## 25. Docker Build Must Be Reproducible

The following should work from a clean checkout:

```bash
docker compose build
docker compose up -d
```

No undocumented local file should be required.

---

## 26. README Integration

Add a Docker section explaining:

- Prerequisites.
- Environment variables.
- Build command.
- Start command.
- Stop command.
- Logs command.
- Application URL.
- Swagger URL.
- OpenAPI URL.
- Health endpoint.
- How to reset local volumes.

---

## 27. Required Agent Workflow

When asked to dockerize the project:

1. Read all instruction files.
2. Inspect Java and Spring Boot versions.
3. Inspect project dependencies.
4. Create `.dockerignore`.
5. Create a multi-stage `Dockerfile`.
6. Configure a non-root runtime when practical.
7. Externalize configuration.
8. Create `.env.example`.
9. Create/update `docker-compose.yml`.
10. Add dependency services if needed.
11. Add health checks.
12. Build the project.
13. Run all tests.
14. Build Docker images.
15. Start the Compose stack.
16. Verify container health.
17. Verify application endpoint.
18. Verify Swagger/OpenAPI.
19. Verify Cucumber reports remain functional.
20. Update README.
21. Fix all issues before completing the task.

---

## 28. Completion Criteria

Dockerization is complete only when:

- Dockerfile exists.
- `.dockerignore` exists.
- Docker Compose configuration exists.
- Application image builds successfully.
- Application runs successfully.
- Runtime configuration is externalized.
- No real secrets are committed.
- Container health can be determined.
- Project tests pass.
- Docker Compose stack starts from a clean checkout.
- Documentation includes Docker usage.
- Observability services integrate when the observability instructions are enabled.

---

## Priority

This file defines project containerization.

It must remain compatible with API-first, testing, Swagger/OpenAPI, Lombok/MapStruct, and observability requirements.
