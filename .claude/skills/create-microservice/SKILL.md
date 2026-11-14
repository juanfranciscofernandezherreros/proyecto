---
name: create-microservice
description: Scaffold a full-featured Spring Boot 3 / Java 17 CRUD microservice (entity, two-tier testing, OpenAPI, Lombok+MapStruct, Docker, Prometheus/Loki/Grafana, Allure) from one instruction, phase by phase with real verification and explicit commit gates.
---

# create-microservice

Turns one instruction like "crea una API CRUD para gestionar resultados de
partidos. Crea la entidad Results con los campos que consideres necesarios"
into a complete, production-shaped microservice — the same stack this repo
already has, built phase by phase instead of ten separate requests.

## Input

Parse `$ARGUMENTS` (or the user's message) for:
- **Entity name** (e.g. "Results", "Orders", "Invoices").
- **Fields**, if given. If not given, choose sensible fields for the domain
  and state the choice out loud before writing code — don't ask unless the
  domain is genuinely ambiguous.
- **Base package / module name**, if given. Default to the existing project's
  package if run inside one; otherwise `com.example.<entity>base`.

## Source of truth

Each phase below has its own standalone skill, installed **globally**
(`~/.claude/skills/<name>/SKILL.md`) so it is available in every project,
not just this one — and each can also be invoked on its own (e.g. `/crud`,
`/pagination-filtering`) when you only want one phase applied in isolation:

`crud`, `pagination-filtering`, `english-javadoc`, `cucumber-api-testing`,
`swagger-openapi`, `service-testing`, `lombok-mapstruct`, `api-first`,
`dockerization`, `hikari-tuning`, `observability-grafana`,
`request-logging-dashboard`, `allure-cucumber-reporting`,
`explicit-bean-wiring`.

Invoke each by name (via the Skill mechanism, not by manually reading a file
path) so it resolves correctly whether a project-local copy under
`.claude/skills/` overrides it or not — **a project-local copy, if one
exists, takes precedence over the global one** and should be read and
followed exactly, since it may carry project-specific refinements. Only if
a phase skill is entirely unavailable (neither project-local nor global —
shouldn't happen once these are installed globally) fall back to the
embedded checklist below for that phase.

## Ground rules

- **Verify, don't claim.** After each phase, actually run the relevant
  command (`mvn test`, `mvn verify`, `docker compose up -d` + a live curl,
  etc.) and read the real output before moving on. A phase that "should work"
  is not done.
- **Never commit or push proactively.** Stage each phase's changes so the
  work is inspectable, but only run `git commit`/`git push` when the user
  explicitly asks (e.g. "comit y push"). This holds for every phase, not just
  the last one.
- **Windows/VS Code gotcha**: the redhat.java language server can write
  corrupted bytecode into `target/classes` alongside Maven, causing
  intermittent `NoSuchBeanDefinitionException` on `mvn clean verify` that has
  nothing to do with the code. Before any build that must be trusted, kill
  stray `java.exe` processes rooted under `*redhat.java*` and `rm -rf target`
  first.
- Keep commit-message style consistent with the repo's existing history
  (concise, why-focused, `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
  trailer), and prefer new commits over amends.

## Phases

Work through these in order. Each phase ends with a one-line status (built +
verified) before starting the next — don't silently batch multiple phases.

1. **CRUD core** — entity (JPA, `@Id`/`@GeneratedValue(IDENTITY)`), request/response
   DTOs, repository (`JpaRepository`), mapper, service interface + impl,
   controller (`/api/<entities>`, standard 5 REST verbs), a
   `@RestControllerAdvice` for 404/400 error shapes. Verify: `mvn spring-boot:run`
   and exercise each endpoint with curl.
2. **Pagination & filtering** — the listing endpoint from phase 1 becomes
   paginated (`Pageable`) and filterable by every entity field via a dynamic
   `Specification` (exact match for id/numeric/date, case-insensitive
   partial match for strings), returning `PagedModel<ResponseDTO>` (`content`
   + `page` envelope), not a bare array. Verify: curl the endpoint with
   combined filter + `page`/`size` params and read the real JSON back.
3. **English JavaDoc** — every public interface method gets an English
   JavaDoc comment describing contract, params, return, exceptions.
4. **Cucumber API tests — 80% coverage, not 100%.** Classic JUnit4
   `@RunWith(Cucumber.class)` runner (`cucumber-junit`), forced onto the
   `surefire-junit4` provider via Failsafe, bound to `integration-test`/`verify`.
   Do not use the JUnit5 `@Suite`/`cucumber-junit-platform-engine` approach —
   it has been found to silently report 0 failures on a real Cucumber failure
   with this Surefire setup. Cover the golden paths and the obvious negative
   cases, including a couple of filter/pagination scenarios; skip exhaustive
   edge cases (that's the service-test phase's job). Verify: `mvn verify` and
   confirm the reports mention Cucumber scenarios.
5. **Swagger / OpenAPI** — `springdoc-openapi-starter-webmvc-ui:2.8.9`
   specifically (2.9.0 breaks with Spring Framework 6.2's `PathPatternParser`
   — do not use it). `@Tag`/`@Operation(operationId=...)`/`@ApiResponses`/
   `@Parameter` on every endpoint, `@ParameterObject` on the filter DTO and
   `Pageable`, an `OpenApiConfig` bean for title/version/contact. Verify: hit
   `/swagger-ui/index.html` and `/v3/api-docs` live.
6. **Service unit tests — 100% of paths.** JUnit 5 + Mockito + AssertJ,
   every branch (happy path, not-found, validation failure) for every service
   method, plus a dedicated `@DataJpaTest` against real H2 for the
   Specification-building logic (a mocked repository can't catch a wrong
   `criteriaBuilder` call). If the service depends on `MeterRegistry`,
   construct it manually with a real `SimpleMeterRegistry` instead of mocking
   it. Verify: `mvn test` with a coverage tool or manual branch inventory.
7. **Lombok + MapStruct** — `@Getter @Setter @NoArgsConstructor
   @AllArgsConstructor @Builder` on entity/DTOs, MapStruct
   (`componentModel="spring"`) interface for entity↔DTO with an
   `@MappingTarget` update method. Annotation processor order in
   `maven-compiler-plugin` matters: Lombok → mapstruct-processor →
   `lombok-mapstruct-binding`. Verify: `mvn clean compile` and inspect the
   generated `*MapperImpl`.
8. **API-First** — export `docs/openapi.json`/`.yaml` from the running app
   (`GET /v3/api-docs[.yaml]`) as the committed contract; note in the README
   that contract, controller, DTOs, and Cucumber scenarios must move together.
9. **Dockerization** — multi-stage Dockerfile (`maven:3.9-eclipse-temurin-17`
   build → `eclipse-temurin:17-jre` run), non-root user, `HEALTHCHECK` on
   `/actuator/health`, `.dockerignore`, `.env.example`, `docker-compose.yml`.
   Verify: `docker compose build && docker compose up -d` then curl the health
   endpoint through the container.
10. **Hikari tuning** — explicit `spring.datasource.hikari.*` (pool name,
    size, timeouts, leak detection) instead of Spring Boot's implicit
    defaults, plus a test proving 3x the pool's max size worth of concurrent
    callers are all served without connection errors. Verify: run the test
    and read the pool name in the startup log.
11. **Observability** — Actuator + Micrometer + `micrometer-registry-prometheus`,
    custom business counters where meaningful (watch for the `_created`
    Prometheus/OpenMetrics reserved-suffix pitfall — never name a counter
    ending in `.created`), a structured HTTP access-log line per request
    (see `request-logging-dashboard`), plus Prometheus + Loki + Grafana
    Alloy + Grafana wired into the same compose network with provisioned
    datasources and a real dashboard organized into rows (traffic/errors,
    business metrics, JVM/runtime, connection pool with a utilization gauge,
    logs) — not a placeholder or an unstructured wall of panels. Verify:
    query Prometheus/Grafana's HTTP APIs live (through Grafana's own
    datasource proxy, not just raw Prometheus/Loki) and confirm every panel
    returns data, not just that containers are "Up".
12. **Allure reporting** — `allure-cucumber7-jvm` plugin wired into the
    Cucumber runner, an HTTP-evidence attachment helper (request/response,
    method/url/headers/body) with sensitive header/field masking, on every
    step. Verify: `mvn verify` then `mvn allure:report`, and confirm
    `target/allure-results/*.json` actually contains attached HTTP evidence.
13. **Explicit bean wiring** — replace `@Service`/`@Component` on the
    service impl, mapper, and filter with a central `BeanConfig`
    `@Configuration` class of `@Bean` methods; `@RestController` and
    `@RestControllerAdvice` stay on their classes (Spring MVC requires them
    for handler/advice detection) but get excluded from component scanning
    and instantiated by `BeanConfig` too; the Spring Data JPA repository is
    the one thing left alone, since it's a reflection-generated proxy, not a
    plain class. Watch for the `@DataJpaTest`-breaks-on-`MeterRegistry`
    pitfall this causes — fix with `@Lazy` on both the bean definition *and*
    the injection point that consumes it (one alone isn't enough). Verify:
    `mvn clean verify` (a slice test failing on an unrelated bean is this
    pitfall, not a new bug) and exercise a real endpoint, a real 404, and
    the access-log filter against the live app.

## End of run

Summarize what was built and what was actually verified (commands run, real
output seen) per phase — not a plan, a report of what happened. Then stop and
wait; do not commit or push until asked.
