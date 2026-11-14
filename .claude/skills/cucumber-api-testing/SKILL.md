---
name: cucumber-api-testing
description: Add Cucumber end-to-end API tests (real HTTP, ~80% of paths) covering success, validation, not-found, and malformed-request scenarios for every endpoint.
---

# Cucumber API Testing and Reporting Instructions

## Objective

All REST APIs in this project must include automated end-to-end API tests using Cucumber.

The tests must validate the behavior of every endpoint through real HTTP requests or the Spring HTTP test layer, not by calling service methods directly.

The test suite must cover successful flows, validation failures, missing resources, malformed requests, boundary cases, duplicate data when applicable, and other meaningful edge cases.

These instructions must be followed together with:

- `CRUD_INSTRUCTIONS.md`
- `ENGLISH_PROJECT_INSTRUCTIONS.md`

All test code, feature files, scenario names, comments, variables, error messages, and reports must be written in English.

---

## Required Testing Stack

Use:

- Cucumber
- JUnit
- Spring Boot Test
- MockMvc or RestAssured
- H2 test database
- Maven

Prefer RestAssured for HTTP-level tests when practical.

---

## Required Test Structure

Use the following structure:

```text
src/test/java/
└── com/example/project/
    └── cucumber/
        ├── CucumberTest.java
        ├── CucumberSpringConfiguration.java
        └── steps/
            └── ResultStepDefinitions.java

src/test/resources/
└── features/
    └── results.feature
```

---

## Spring Test Configuration

Cucumber tests must run with the Spring Boot application context.

Use a dedicated test configuration and an isolated test database.

Example:

```java
@CucumberContextConfiguration
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class CucumberSpringConfiguration {
}
```

Use the appropriate configuration when MockMvc is selected instead of a random HTTP port.

---

## Endpoint Testing Rule

Every REST endpoint must be tested through the API layer.

For an entity exposed at:

```text
/api/results
```

test at minimum:

```text
GET    /api/results
GET    /api/results/{id}
POST   /api/results
PUT    /api/results/{id}
DELETE /api/results/{id}
```

Do not consider the endpoint tested if only repository or service methods are exercised.

---

## Mandatory Scenarios

### GET collection

Test at minimum:

- HTTP 200 when the collection exists.
- Empty array when the database contains no records.
- One returned record.
- Multiple returned records.
- Expected JSON structure.
- Expected field values.
- Correct content type.
- No unexpected server errors.

### GET by ID

Test at minimum:

- Existing ID returns HTTP 200.
- Correct object is returned.
- Unknown ID returns HTTP 404.
- Invalid ID format returns the expected client error.
- Negative ID is handled correctly.
- Zero ID is handled correctly.
- Response body matches the API error contract when an error occurs.

### POST

Test at minimum:

- Valid payload creates a resource.
- HTTP 201 is returned.
- Generated ID is present.
- Generated ID is not provided by the client when the API contract forbids it.
- Created object contains expected values.
- Resource is persisted and can be retrieved afterward.
- Required field missing.
- Required field null.
- Empty string where prohibited.
- Blank string where prohibited.
- Invalid field type.
- Invalid JSON.
- Unknown JSON fields according to project configuration.
- Boundary values.
- Strings exceeding configured maximum length.
- Negative numeric values when prohibited.
- Duplicate values when uniqueness rules exist.
- Invalid enum value when enums are used.
- Invalid date or time formats when applicable.

### PUT

Test at minimum:

- Existing resource can be fully updated.
- HTTP 200 is returned for a successful update.
- Returned object contains updated values.
- Updated object is persisted.
- Unknown ID returns HTTP 404.
- Invalid ID format.
- Invalid request payload.
- Required field missing.
- Null values when prohibited.
- Boundary values.
- Attempt to change immutable fields.
- Client-provided ID conflicts with the path ID.
- Duplicate unique fields when applicable.

### PATCH

If PATCH exists, test:

- Single field update.
- Multiple field update.
- Unknown ID.
- Invalid field.
- Invalid value.
- Attempt to update immutable fields.
- Empty patch body.

### DELETE

Test at minimum:

- Existing resource can be deleted.
- Successful deletion returns HTTP 204.
- Deleted resource can no longer be retrieved.
- Unknown ID returns the expected status.
- Invalid ID format.
- Repeated deletion of the same resource.
- Referential integrity behavior when applicable.

---

## Validation Coverage

Every validation rule defined in DTOs or entities must have at least one positive and one negative Cucumber scenario where meaningful.

Examples include:

```text
@NotNull
@NotBlank
@Size
@Min
@Max
@Positive
@PositiveOrZero
@Email
@Pattern
```

If a new validation rule is added, corresponding scenarios must also be added.

---

## Boundary Testing

Test meaningful boundary values.

Examples:

```text
minimum - 1
minimum
minimum + 1
maximum - 1
maximum
maximum + 1
```

For strings, test:

- Empty value
- Blank value
- Minimum length
- Maximum length
- Over maximum length
- Unicode characters
- Special characters when applicable

---

## Data Isolation

Each scenario must be independent.

Tests must not depend on execution order.

Use one or more of these strategies:

- Clean the database before each scenario.
- Use transactions with rollback.
- Create scenario-specific test data.
- Use dedicated fixtures.

Never depend on data left behind by a previous scenario.

---

## Feature File Quality

Feature files must describe behavior, not implementation details.

Prefer:

```gherkin
Feature: Manage results

  Scenario: Create a valid result
    Given the results database is empty
    When I create a result with valid data
    Then the response status should be 201
    And the response should contain a generated id
    And the result should be stored in the database
```

Avoid scenarios that expose internal service or repository implementation details.

---

## Scenario Outlines

Use `Scenario Outline` for input combinations and validation matrices.

Example:

```gherkin
Scenario Outline: Reject invalid result payloads
  Given the results database is empty
  When I create a result with homeTeam "<homeTeam>"
  Then the response status should be <status>

  Examples:
    | homeTeam | status |
    |          | 400    |
    |         | 400    |
```

Use data tables when they improve readability.

---

## API Error Contract Testing

Error responses must be tested.

Verify fields such as:

```json
{
  "status": 404,
  "error": "Not Found",
  "message": "Result not found",
  "path": "/api/results/999"
}
```

Adapt the assertions to the project's actual error response contract.

Tests must validate both HTTP status and important response-body fields.

---

## Response Contract Testing

For successful responses, verify:

- HTTP status.
- Content type.
- Required JSON properties.
- Property types.
- Important property values.
- Generated identifiers.
- Absence of fields that must not be exposed.

---

## Cucumber Step Definitions

Step definitions must:

- Be reusable.
- Be clearly named.
- Avoid duplicated HTTP request code.
- Avoid duplicated JSON parsing code.
- Keep scenario state isolated.
- Use helper methods where appropriate.

Do not put business logic into step definitions.

---

## Automatic Test Report

Every Cucumber test execution must generate a clear human-readable report.

At minimum, generate:

```text
target/cucumber-reports/cucumber.html
target/cucumber-reports/cucumber.json
```

The HTML report is mandatory.

The JSON report must be generated so that CI systems or additional reporting tools can consume the results.

If supported by the selected Cucumber version, also generate a JUnit XML report:

```text
target/cucumber-reports/cucumber.xml
```

---

## Report Requirements

The report must clearly show:

- Feature name.
- Scenario name.
- Passed scenarios.
- Failed scenarios.
- Skipped scenarios.
- Step results.
- Failure messages.
- Stack traces or useful failure details.
- Execution duration.

A developer must be able to identify a failing endpoint and scenario without reading Maven console output.

---

## Cucumber Report Configuration

Configure the Cucumber runner/plugins to produce reports similar to:

```text
pretty
html:target/cucumber-reports/cucumber.html
json:target/cucumber-reports/cucumber.json
junit:target/cucumber-reports/cucumber.xml
```

Use the syntax supported by the actual Cucumber version used by the project.

Do not blindly copy obsolete annotations or runner configuration. Keep dependencies and configuration compatible.

---

## Optional Enhanced Report

When appropriate, configure an enhanced report using a Maven-compatible Cucumber reporting plugin.

The enhanced report should be generated from the Cucumber JSON output and placed under:

```text
target/cucumber-reports/
```

Do not introduce an enhanced reporting dependency if it causes version conflicts or makes the build unstable.

The basic Cucumber HTML report remains mandatory.

---

## Screenshots and HTTP Diagnostics

For failed API scenarios, include useful diagnostic information when practical:

- HTTP method.
- Requested URL.
- Request body.
- Response status.
- Response body.

Never expose passwords, tokens, secrets, or sensitive headers in reports.

---

## Maven Commands

The test suite must run with:

```bash
mvn test
```

If integration tests are intentionally separated, provide a documented Maven command such as:

```bash
mvn verify
```

The standard project build should fail when Cucumber tests fail.

---

## Report Location

After execution, clearly document where the report can be found.

Expected location:

```text
target/cucumber-reports/cucumber.html
```

A developer should be able to open this file directly in a browser.

---

## Test Summary

After the test suite runs, provide a concise summary containing:

- Total scenarios.
- Passed scenarios.
- Failed scenarios.
- Skipped scenarios.
- Report path.

Example:

```text
Cucumber API Test Summary

Total: 24
Passed: 24
Failed: 0
Skipped: 0

HTML report:
target/cucumber-reports/cucumber.html
```

---

## Coverage Rule

For every new or modified endpoint:

1. Review all supported HTTP outcomes.
2. Add happy-path scenarios.
3. Add not-found scenarios.
4. Add validation scenarios.
5. Add malformed-request scenarios where applicable.
6. Add boundary cases.
7. Add business-rule failures.
8. Add persistence verification where appropriate.
9. Run the complete Cucumber suite.
10. Generate the HTML report.
11. Fix failing tests before considering the task complete.

Do not claim that every possible input has been tested literally. The requirement is to cover all meaningful functional paths, validation rules, HTTP outcomes, boundary conditions, and known business rules.

---

## Final Verification

Before considering API testing complete:

- All Cucumber scenarios compile.
- All feature files are in English.
- All step definitions are in English.
- Tests execute through the endpoint.
- Tests are isolated.
- All meaningful endpoint cases are covered.
- All tests pass.
- `mvn test` or the documented build command succeeds.
- The HTML report exists.
- The JSON report exists.
- The report clearly identifies passed and failed scenarios.
- No secrets appear in reports.
- The report path is documented.

---

## Priority

When this file is used together with the other project instructions:

- `CRUD_INSTRUCTIONS.md` defines the API architecture.
- `ENGLISH_PROJECT_INSTRUCTIONS.md` defines the English-only convention.
- This file defines the API testing and reporting requirements.

All three instruction files must be respected before the work is considered complete.
