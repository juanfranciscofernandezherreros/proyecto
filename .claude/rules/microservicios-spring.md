# Global rules

## New microservices from scratch

When asked to create, scaffold, or bootstrap a new Spring Boot microservice
or CRUD API from scratch — in any project, in any wording ("crea una API
CRUD para...", "hazme un microservicio para...", "necesito un servicio que
gestione...") — automatically apply the `create-microservice` skill instead
of waiting to be told which pieces to build. Don't ask permission to use the
skill; just use it. It already builds, in order and each one verified
before moving to the next: CRUD core, pagination & filtering, English
JavaDoc, Cucumber API tests, Swagger/OpenAPI, service unit tests,
Lombok/MapStruct, API-First contract export, Dockerization, HikariCP
tuning, full observability (Prometheus/Loki/Grafana with a business-metrics
dashboard), and Allure reporting.

Still never commit or push without the user explicitly asking, even though
the skill runs unprompted otherwise — that gate always stays manual.

This does not apply to unrelated ad-hoc requests against an *existing*
service (e.g. "add a field to X", "fix this test") — only to building a new
one from nothing.

## CRUD work in existing microservices

When asked to create, extend, or refactor a CRUD capability in an *existing*
Spring Boot 3 / Java 17 project, treat it as a one-shot implementation task:
- Do not ask for permission to scaffold.
- Do not split the work into multiple conversational rounds.
- Infer sensible defaults when the entity name or main fields are clear.
- Follow whatever package layout, entity/DTO/mapper pattern, and
  filtering/pagination approach the project already has — use its existing
  reference entity as the template rather than inventing a new style.

Build the full stack in one pass:
1. Entity / JPA model
2. DTOs, validation, mapper
3. Repository and Specification-based filtering/pagination
4. Service + controller + error handling
5. OpenAPI annotations and docs
6. Tests (unit + Cucumber API acceptance)
7. Observability, Docker, and Allure wiring when the request implies a
   production-style delivery

Preserve whatever bean-wiring style (explicit `@Bean` vs stereotype
annotations) and endpoint naming convention (e.g. `/api/<entity>`) the
project already uses. Keep the implementation aligned with any OpenAPI docs
already present.

Before finishing, verify with the relevant real command:
- `mvn test` for unit/service coverage
- `mvn verify` for API acceptance tests
- `mvn spring-boot:run` or `mvn -DskipTests compile` for a quick sanity check

Prefer the `spring-crud-builder` agent or the `/implement-crud` command to
do this work in a single pass.
