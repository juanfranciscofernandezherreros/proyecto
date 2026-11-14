---
name: api-first
description: Make the OpenAPI contract (docs/openapi.yaml/json) the source of truth that implementation, DTOs, controllers, and tests must conform to.
---

# API-First Development Instructions

## Objective

All REST APIs in this project must follow an API-first development approach.

The API contract must be designed and reviewed before implementation.

OpenAPI is the source of truth for the public API contract.

Implementation, DTOs, controllers, tests, and documentation must conform to the OpenAPI contract.

---

## 1. OpenAPI Is the Contract

Before implementing a new API, create or update:

```text
docs/openapi.yaml
```

or:

```text
docs/openapi.json
```

Prefer YAML for human-maintained API contracts.

The contract must be valid OpenAPI 3.x.

---

## 2. Contract Before Code

The required workflow is:

```text
Business Requirement
      ↓
OpenAPI Contract
      ↓
Contract Review
      ↓
Generated/Implemented API Models and Interfaces
      ↓
Service Implementation
      ↓
Cucumber Tests
      ↓
Swagger Verification
```

Do not start by creating controllers or DTOs before the API contract exists.

---

## 3. Contract Scope

The OpenAPI file must define:

- Paths
- HTTP methods
- Operation IDs
- Request parameters
- Path parameters
- Query parameters
- Request bodies
- Response bodies
- HTTP status codes
- Error responses
- Schemas
- Required fields
- Validation constraints
- Examples
- Security requirements when applicable

---

## 4. Operation IDs

Every operation must have a stable and descriptive `operationId`.

Example:

```yaml
operationId: getResultById
```

Use English names only.

Avoid generic names such as:

```text
method1
execute
handler
```

---

## 5. Resource Naming

Use plural nouns for collection endpoints.

Preferred:

```text
/api/results
/api/users
/api/matches
```

Avoid:

```text
/api/getResults
/api/createResult
```

HTTP methods already express the action.

---

## 6. CRUD Contract

A typical CRUD resource should define:

```text
GET    /api/results
GET    /api/results/{id}
POST   /api/results
PUT    /api/results/{id}
DELETE /api/results/{id}
```

Add PATCH only when partial update semantics are explicitly required.

---

## 7. Request and Response Schemas

Define separate schemas when request and response responsibilities differ.

Prefer:

```text
CreateResultRequest
UpdateResultRequest
ResultResponse
ApiError
```

Do not force one DTO to represent every use case.

---

## 8. Server-Generated IDs

Create requests should not require server-generated IDs.

Example:

```yaml
CreateResultRequest:
  type: object
  required:
    - matchId
    - homeTeam
    - awayTeam
  properties:
    matchId:
      type: string
    homeTeam:
      type: string
    awayTeam:
      type: string
```

Response:

```yaml
ResultResponse:
  type: object
  properties:
    id:
      type: integer
      format: int64
      readOnly: true
```

---

## 9. Validation in the Contract

All important validation rules must be defined in OpenAPI where supported.

Examples:

```yaml
homeTeam:
  type: string
  minLength: 1
  maxLength: 100

homeScore:
  type: integer
  minimum: 0
```

Implementation validation must match the contract.

---

## 10. Error Contract

Define a reusable error schema.

Example:

```yaml
ApiError:
  type: object
  required:
    - status
    - message
  properties:
    timestamp:
      type: string
      format: date-time
    status:
      type: integer
    error:
      type: string
    message:
      type: string
    path:
      type: string
```

Reuse the same error contract across endpoints.

---

## 11. Response Codes

Document only meaningful responses the API actually supports.

Typical examples:

```text
200 OK
201 Created
204 No Content
400 Bad Request
404 Not Found
409 Conflict
422 Unprocessable Entity
500 Internal Server Error
```

Implementation and Cucumber tests must match these documented statuses.

---

## 12. Examples

Every important request and response schema should include realistic examples.

Examples must be valid according to the contract.

---

## 13. API Generation

When the project uses OpenAPI Generator or a similar tool, prefer generating:

- API interfaces
- Request/response models
- Client contracts when needed

Keep generated code separated from handwritten business logic.

Do not manually edit generated files unless the build process explicitly allows it.

---

## 14. Generated Interface Pattern

When practical, generate or maintain API interfaces from the OpenAPI contract.

Then implement them in controllers.

Example concept:

```text
OpenAPI
   ↓
ResultsApi interface
   ↓
ResultsController implements ResultsApi
   ↓
ResultService
```

This reduces contract drift.

---

## 15. Controller Responsibility

Controllers should adapt the API contract to the service layer.

Controllers must not contain business logic.

Flow:

```text
Generated API Interface
      ↓
Controller
      ↓
Service Interface
      ↓
ServiceImpl
      ↓
Repository
```

---

## 16. DTO and Mapper Strategy

If OpenAPI generates API models, treat those models as API-layer DTOs.

Use MapStruct to map:

```text
OpenAPI Model <-> Domain/Entity
```

Do not expose JPA entities directly through the API.

---

## 17. Contract-Driven Cucumber Tests

Cucumber tests must be derived from the OpenAPI contract.

For each operation, test:

- Success response.
- Required field validation.
- Invalid parameter behavior.
- Not-found behavior where relevant.
- Conflict behavior where relevant.
- Boundary values.
- Response schema expectations.

If the contract changes, Cucumber tests must be updated.

---

## 18. Contract Consistency

The following must stay synchronized:

```text
OpenAPI contract
Controller
DTO/API models
Service behavior
Validation
Cucumber tests
Swagger UI
README
```

If any of them disagree, the task is incomplete.

---

## 19. Breaking Changes

Before changing an existing public contract, identify whether the change is breaking.

Examples of breaking changes:

- Removing an endpoint.
- Renaming a path.
- Removing a response field.
- Making an optional field required.
- Changing a field type.
- Changing a success status code.
- Changing authentication requirements.

Do not introduce breaking changes silently.

---

## 20. Backward Compatibility

When compatibility matters, prefer additive changes:

- Add optional fields.
- Add new endpoints.
- Add new enum values only when consumers can tolerate them.
- Version the API when required.

---

## 21. API Versioning

If versioning is required, use a consistent strategy.

Example:

```text
/api/v1/results
```

Do not introduce versioning unless project requirements call for it.

---

## 22. Contract Validation

The OpenAPI file must be validated before implementation is considered complete.

Verify:

- Valid OpenAPI syntax.
- Unique operation IDs.
- Valid `$ref` references.
- Required schemas exist.
- No unresolved references.
- Examples match schema types.
- Response codes match implementation.

---

## 23. Build Integration

When practical, integrate OpenAPI generation or validation into Maven.

The build should fail when generated sources or contract validation fail.

Generated sources must be reproducible from a clean checkout.

---

## 24. Source of Truth Rule

If handwritten controller annotations disagree with `docs/openapi.yaml`, the API-first contract wins unless the contract is intentionally being changed.

Any intentional contract change must first update the OpenAPI file.

---

## 25. Swagger UI

Swagger UI must render the same contract used by the implementation.

Do not maintain two independent API definitions.

The documented Swagger UI must reflect `docs/openapi.yaml` or the generated equivalent.

---

## 26. README

README must document:

- OpenAPI contract location.
- How to validate/generate the API.
- How to run the application.
- Swagger UI location.
- How to run tests.
- Cucumber report location.

---

## 27. Required Agent Workflow

When asked to create a new API:

1. Read all project instruction files.
2. Understand the requested business resource.
3. Create/update `docs/openapi.yaml`.
4. Define paths and schemas.
5. Define validation.
6. Define examples.
7. Define errors.
8. Validate the OpenAPI contract.
9. Generate or implement API interfaces/models from the contract.
10. Implement the controller.
11. Implement the service interface.
12. Implement the service implementation.
13. Implement repository logic.
14. Implement MapStruct mappings.
15. Add Lombok where required by project conventions.
16. Add service unit tests.
17. Add Cucumber endpoint tests.
18. Run all tests.
19. Generate Cucumber HTML report.
20. Verify Swagger UI.
21. Verify OpenAPI export.
22. Fix all failures and contract inconsistencies.
23. Run the complete Maven build.

---

## 28. Completion Criteria

An API-first task is complete only when:

- OpenAPI contract exists first.
- Contract validates successfully.
- Every implemented endpoint exists in the contract.
- Every contract endpoint is implemented.
- Request/response schemas match implementation.
- Validation matches the contract.
- Status codes match.
- Error contract matches.
- Cucumber tests reflect the contract.
- Swagger UI reflects the contract.
- Service tests pass.
- Cucumber tests pass.
- Maven build succeeds.
- No undocumented breaking changes exist.

---

## Priority

This file defines the API-first workflow.

When combined with the other project instructions:

- CRUD instructions define architecture.
- English instructions define language.
- Lombok/MapStruct instructions define boilerplate and mapping rules.
- Service testing instructions define service unit tests.
- Cucumber instructions define endpoint acceptance tests and reports.
- Swagger/OpenAPI instructions define documentation.
- This file makes the OpenAPI contract the starting point and source of truth.
