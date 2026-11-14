---
name: allure-cucumber-reporting
description: Integrate Allure with the Cucumber API test suite, attaching real request/response HTTP evidence (masked) to every scenario.
---

# Allure + Cucumber API Reporting Instructions

## Objective

All Cucumber API tests must integrate with Allure. Every executed HTTP scenario must provide enough evidence to inspect the request, response, assertions, and failure details.

The `.feature` files must remain readable business specifications. Request payloads and expected response examples should be visible in Gherkin when useful. The actual runtime request and response must be attached to Allure.

All feature files, scenarios, steps, attachments, comments, test code, and report descriptions must be written in English.

## Required Stack

Use compatible versions of:

- Cucumber
- JUnit 5
- Allure
- Allure Cucumber adapter
- RestAssured when practical
- Spring Boot Test
- Maven

Do not mix incompatible JUnit/Cucumber adapters.

## Mandatory Outputs

Every Cucumber execution must generate:

```text
target/allure-results/
target/cucumber-reports/cucumber.html
target/cucumber-reports/cucumber.json
target/cucumber-reports/cucumber.xml
```

The project must also provide a documented command that generates:

```text
target/allure-report/index.html
```

Allure does not replace the existing Cucumber HTML report.

## Mandatory HTTP Evidence

Every HTTP request must be attached to Allure.

Every HTTP response must be attached to Allure.

This applies to passed and failed scenarios.

For each request, capture:

```text
HTTP method
URL
Path parameters
Query parameters
Safe headers
Request body
```

For each response, capture:

```text
HTTP status
Relevant response headers
Response body
```

A developer must be able to diagnose a failed API scenario from Allure without reproducing the request manually.

## Request Attachment

Use a clear attachment name such as:

```text
HTTP Request
```

Example content:

```text
Method: POST
URL: http://localhost:8080/api/results
Content-Type: application/json

{
  "matchId": "MATCH-2026-001",
  "homeTeam": "Real Madrid",
  "awayTeam": "Barcelona",
  "homeScore": 2,
  "awayScore": 1
}
```

## Response Attachment

Use a clear attachment name such as:

```text
HTTP Response
```

Example content:

```text
Status: 201
Content-Type: application/json

{
  "id": 1,
  "matchId": "MATCH-2026-001",
  "homeTeam": "Real Madrid",
  "awayTeam": "Barcelona",
  "homeScore": 2,
  "awayScore": 1
}
```

The response must contain the actual runtime response, not a hardcoded copy.

## Pretty JSON

Pretty-print JSON request and response bodies before attaching them whenever possible.

Prefer the MIME type:

```text
application/json
```

If the body is not JSON, attach it using an appropriate text or content MIME type.

## Request Bodies in Feature Files

When a scenario sends JSON, show the payload directly in the `.feature` file using a DocString when useful.

Example:

```gherkin
Feature: Results API

  Scenario: Create a valid result
    Given the results database is empty
    When I send a POST request to "/api/results" with body:
      """
      {
        "matchId": "MATCH-2026-001",
        "homeTeam": "Real Madrid",
        "awayTeam": "Barcelona",
        "homeScore": 2,
        "awayScore": 1
      }
      """
    Then the response status should be 201
    And the response field "id" should not be null
```

The exact runtime request must additionally appear in Allure.

## Expected Responses in Feature Files

When useful for contract testing, expected response content may also be declared in the feature.

Example:

```gherkin
And the response should contain:
  """
  {
    "matchId": "MATCH-2026-001",
    "homeTeam": "Real Madrid",
    "awayTeam": "Barcelona",
    "homeScore": 2,
    "awayScore": 1
  }
  """
```

Do not hardcode generated IDs, timestamps, random values, or other dynamic fields unless the test controls them.

Validate dynamic values separately.

## Actual Responses

Do not modify `.feature` files after execution to insert actual responses.

The rule is:

```text
.feature -> request + expected behavior
Allure   -> actual request + actual response + execution evidence
```

The actual response must be captured at runtime and attached to Allure.

## Reusable HTTP Steps

Prefer reusable steps:

```gherkin
When I send a GET request to "/api/results"
When I send a GET request to "/api/results/1"
When I send a POST request to "/api/results" with body:
When I send a PUT request to "/api/results/1" with body:
When I send a DELETE request to "/api/results/1"
```

Do not duplicate HTTP execution code for every resource.

## Scenario Context

Use scenario-scoped state for the current interaction.

Conceptually store:

```java
RequestSpecification request;
Response response;
String requestBody;
String requestUrl;
String httpMethod;
```

Do not use unsafe static mutable state shared between scenarios.

## Allure HTTP Helper

Create a reusable component such as:

```text
AllureHttpAttachment
```

It should centralize operations such as:

```text
attachRequest
attachResponse
attachJson
attachText
sanitizeHeaders
sanitizeBody
```

Do not duplicate Allure attachment logic across step definition classes.

## RestAssured Integration

When RestAssured is used, centralize HTTP evidence collection with a filter or shared request executor.

Capture:

```text
method
URI
headers
request body
response status
response headers
response body
```

Do not rely only on RestAssured console logging.

## Passed and Failed Scenarios

Attach requests and responses for both:

```text
PASSED
FAILED
```

Successful scenarios serve as executable API examples.

Failed scenarios provide diagnostic evidence.

## Failure Diagnostics

A failed Allure scenario must make visible:

```text
Feature
Scenario
Failed step
Expected value
Actual value
HTTP Request
HTTP Response
Assertion failure
Stack trace when useful
Execution duration
```

## Secret Sanitization

Never expose secrets in Allure, Cucumber reports, Maven output, or logs.

Mask headers such as:

```text
Authorization
Proxy-Authorization
Cookie
Set-Cookie
X-API-Key
API-Key
```

Mask JSON properties such as:

```text
password
token
accessToken
refreshToken
secret
clientSecret
apiKey
```

Replace values with:

```text
***MASKED***
```

Sanitize before creating the Allure attachment.

## Authentication Tests

Authentication requests and responses must also be attached, but credentials and tokens must be masked.

Example:

```json
{
  "username": "test-user",
  "password": "***MASKED***"
}
```

Never expose a real JWT in the report.

## Status Assertions

Every API scenario must explicitly validate its HTTP status.

Example:

```gherkin
Then the response status should be 201
```

Allure must show the actual response status.

## JSON Assertions

Create reusable JSON assertion steps.

Examples:

```gherkin
And the response field "id" should not be null
And the response field "matchId" should be "MATCH-2026-001"
And the response field "homeScore" should be 2
And the response should be an array
```

Use JSONPath or another appropriate JSON assertion mechanism.

## Error Responses

Negative scenarios must attach the complete sanitized error response.

Example:

```gherkin
Scenario: Get an unknown result
  When I send a GET request to "/api/results/999999"
  Then the response status should be 404
  And the response field "message" should be "Result not found"
```

Allure must show the actual request and actual 404 response.

## Scenario Outlines

Use Scenario Outline for validation matrices.

Example:

```gherkin
Scenario Outline: Reject invalid home scores
  When I send a POST request to "/api/results" with body:
    """
    {
      "matchId": "MATCH-001",
      "homeTeam": "Team A",
      "awayTeam": "Team B",
      "homeScore": <homeScore>,
      "awayScore": 1
    }
    """
  Then the response status should be <status>

  Examples:
    | homeScore | status |
    | -1        | 400    |
    | 0         | 201    |
```

Each Examples row must produce independently understandable Allure results.

## Tags

Use meaningful tags when useful:

```text
@api
@crud
@positive
@negative
@validation
@smoke
@regression
```

Resource tags such as `@results` or `@users` are encouraged.

## Allure Metadata

When supported and meaningful, populate:

```text
Epic
Feature
Story
Severity
Owner
Tags
```

Do not invent owners or meaningless severity levels.

## Correlation IDs

If the application supports correlation IDs, expose the correlation ID in the Allure evidence.

This should make it possible to correlate:

```text
Allure scenario
    ↓
HTTP Request / Response
    ↓
Correlation ID
    ↓
Loki logs
```

Do not use correlation IDs as Prometheus metric labels.

## Application Logs on Failure

When practical, attach a focused sanitized application log excerpt for failed scenarios.

Do not attach huge log files to every test.

## Feature Organization

Prefer one feature per resource or cohesive behavior:

```text
src/test/resources/features/
├── results.feature
├── users.feature
└── matches.feature
```

For large resources, split by operation:

```text
results-create.feature
results-read.feature
results-update.feature
results-delete.feature
results-validation.feature
```

## CRUD Coverage

Request/response Allure evidence is mandatory for all implemented operations:

```text
GET collection
GET by ID
POST
PUT
PATCH
DELETE
```

This applies to positive and negative scenarios.

## API-First Consistency

Feature payloads and assertions must follow the OpenAPI contract.

For example:

```text
OpenAPI: POST /api/results -> 201
Cucumber: assert 201
Allure: show actual 201 response
```

If OpenAPI, implementation, and tests disagree, fix the inconsistency.

## Allure Report Generation

Generate Allure results during test execution.

Then generate the HTML report from:

```text
target/allure-results/
```

Preferred output:

```text
target/allure-report/
```

When Allure CLI is available, typical commands are:

```bash
allure generate target/allure-results --clean -o target/allure-report
allure open target/allure-report
```

If the project uses an Allure Maven plugin, document and use the compatible Maven commands instead.

## Maven

The normal complete test workflow should use:

```bash
mvn clean verify
```

or the project's documented equivalent.

A failed Cucumber scenario must fail the Maven build.

## Expected Output

After complete execution:

```text
target/
├── allure-results/
├── allure-report/
│   └── index.html
├── cucumber-reports/
│   ├── cucumber.html
│   ├── cucumber.json
│   └── cucumber.xml
└── surefire-reports/
```

If JaCoCo is configured:

```text
target/site/jacoco/index.html
```

## Automatic Verification

Before claiming success, verify that:

```text
target/allure-results/
```

exists and contains Allure result files.

Verify:

```text
target/allure-report/index.html
```

exists after report generation.

Verify:

```text
target/cucumber-reports/cucumber.html
```

exists.

Do not claim that a report was generated without checking the actual artifact.

## README

Document:

```text
How to run Cucumber
How to generate Allure results
How to generate Allure HTML
How to open Allure HTML
Allure report path
Cucumber report path
```

Use the actual commands supported by the project.

## Required Agent Workflow

When creating or modifying Cucumber tests:

1. Read all project instruction files.
2. Read the OpenAPI contract.
3. Identify affected endpoints.
4. Create or update feature scenarios.
5. Include readable request payloads in Gherkin where useful.
6. Include expected response examples where useful.
7. Implement reusable HTTP steps.
8. Execute the actual HTTP request.
9. Capture and sanitize the request.
10. Attach the request to Allure.
11. Capture and sanitize the response.
12. Attach the response to Allure.
13. Execute assertions.
14. Run all Cucumber scenarios.
15. Fix failures.
16. Verify Cucumber HTML.
17. Verify Allure results.
18. Generate Allure HTML.
19. Verify `target/allure-report/index.html`.
20. Run the complete Maven build.
21. Update README when needed.
22. Do not finish until tests and reports succeed.

## Completion Criteria

The task is complete only when:

- Cucumber tests pass.
- Allure is correctly integrated.
- Allure result files are generated.
- Allure HTML is generated.
- Cucumber HTML remains available.
- Every API scenario attaches its actual request.
- Every API scenario attaches its actual response.
- Request JSON is readable.
- Response JSON is readable.
- Feature files show request payloads where useful.
- Feature files show expected responses where useful.
- Runtime responses are visible in Allure.
- Negative responses are visible in Allure.
- Secrets are masked.
- Failed scenarios contain useful diagnostics.
- OpenAPI and Cucumber remain synchronized.
- Maven build succeeds.
- README documents report generation.

## Priority

This file defines Allure reporting and HTTP evidence for Cucumber API tests.

It complements:

- API-first instructions.
- CRUD instructions.
- Lombok/MapStruct instructions.
- Service testing instructions.
- Cucumber API testing instructions.
- Swagger/OpenAPI instructions.
- Dockerization instructions.
- Grafana/Prometheus/Loki observability instructions.

All applicable instruction files must be respected before the project is considered complete.
