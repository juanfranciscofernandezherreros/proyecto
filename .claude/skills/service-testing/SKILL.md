---
name: service-testing
description: Add comprehensive service-layer unit tests covering 100% of paths, plus a Cucumber HTML report.
---

# Service Testing and Cucumber HTML Report Instructions

## Objective

Every service implementation in this project must have comprehensive automated tests.

In addition, the Cucumber API test suite must always generate a clear HTML report.

These instructions must be followed together with:

- `CRUD_INSTRUCTIONS.md`
- `ENGLISH_PROJECT_INSTRUCTIONS.md`
- `CUCUMBER_API_TESTING_INSTRUCTIONS.md`
- `SWAGGER_OPENAPI_INSTRUCTIONS.md`

All test classes, test methods, comments, fixtures, scenario names, assertions, display names, and report-related descriptions must be written in English.

---

# 1. Two Different Test Levels Are Mandatory

The project must contain both:

## API / Acceptance Tests

Use Cucumber to test REST endpoints through HTTP.

These tests validate the complete API behavior:

```text
HTTP Request
    ↓
Controller
    ↓
Service
    ↓
Repository
    ↓
Database
```

## Service Unit Tests

Use JUnit and Mockito to test every service implementation directly and in isolation.

These tests validate:

```text
ServiceImpl
    ↓
Mocked Repository / Mapper / Dependencies
```

Do not replace service unit tests with Cucumber tests.

Do not replace Cucumber endpoint tests with service unit tests.

Both levels are required.

---

# 2. Required Service Testing Stack

Use:

- JUnit 5
- Mockito
- AssertJ or JUnit assertions
- Maven Surefire

Use Spring Boot Test only when a service test genuinely requires the Spring context.

Prefer pure unit tests for service implementations.

---

# 3. Service Test Structure

For every service implementation:

```text
src/main/java/.../service/impl/ResultServiceImpl.java
```

create:

```text
src/test/java/.../service/impl/ResultServiceImplTest.java
```

Example structure:

```text
src/test/java/com/example/project/
├── service/
│   └── impl/
│       ├── ResultServiceImplTest.java
│       ├── UserServiceImplTest.java
│       └── MatchServiceImplTest.java
└── cucumber/
    ├── CucumberTest.java
    ├── CucumberSpringConfiguration.java
    └── steps/
```

Every concrete service class must have a corresponding test class.

---

# 4. Mockito Isolation

Mock external collaborators such as:

- Repositories
- Mappers
- External API clients
- Message publishers
- File systems
- Clock/time providers when relevant
- Other services when they are true external collaborators of the unit under test

Example:

```java
@ExtendWith(MockitoExtension.class)
class ResultServiceImplTest {

    @Mock
    private ResultRepository repository;

    @Mock
    private ResultMapper mapper;

    @InjectMocks
    private ResultServiceImpl service;
}
```

Do not start the complete Spring application context for a normal service unit test.

---

# 5. Test Every Public Service Method

Every public method declared by a project service interface and implemented by a service implementation must have tests.

For a CRUD service such as:

```java
List<ResultDTO> findAll();

ResultDTO findById(Long id);

ResultDTO create(ResultDTO dto);

ResultDTO update(Long id, ResultDTO dto);

void delete(Long id);
```

all five operations must be thoroughly tested.

If additional service methods are added later, corresponding tests must also be added.

---

# 6. findAll Tests

Test at minimum:

- Repository returns an empty list.
- Repository returns one entity.
- Repository returns multiple entities.
- Every entity is mapped to the expected DTO.
- Returned values are correct.
- Repository is called exactly as expected.
- Mapper is called for every entity.
- Unexpected repository exceptions are not silently swallowed unless business requirements explicitly require handling them.

Example test names:

```text
shouldReturnEmptyListWhenNoResultsExist
shouldReturnAllResults
shouldMapAllEntitiesToDtos
shouldCallRepositoryOnceWhenFindingAllResults
```

---

# 7. findById Tests

Test at minimum:

- Existing ID.
- Correct entity is retrieved.
- Entity is mapped to DTO.
- Correct DTO is returned.
- Unknown ID.
- Correct not-found exception is thrown.
- Mapper is not called when entity does not exist.
- Repository receives the correct ID.

Example:

```text
shouldReturnResultWhenIdExists
shouldThrowResourceNotFoundExceptionWhenIdDoesNotExist
shouldNotCallMapperWhenResultDoesNotExist
```

---

# 8. create Tests

Test at minimum:

- Valid DTO.
- DTO is mapped to entity.
- Repository saves the entity.
- Saved entity is mapped back to DTO.
- Generated ID is returned.
- Server-generated ID is not incorrectly trusted from client input.
- Business validation is enforced.
- Duplicate values are rejected when uniqueness rules exist.
- Repository is not called when business validation fails.
- Mapper interactions are correct.

Example:

```text
shouldCreateResult
shouldReturnGeneratedIdAfterCreatingResult
shouldRejectDuplicateMatchId
shouldNotSaveResultWhenValidationFails
```

---

# 9. update Tests

Test at minimum:

- Existing resource.
- Existing entity is loaded first.
- Allowed fields are updated.
- Immutable fields are preserved.
- Updated entity is saved.
- Saved entity is mapped to DTO.
- Correct DTO is returned.
- Unknown ID throws the correct exception.
- Repository save is not called when the resource does not exist.
- Invalid business data is rejected.
- Duplicate unique fields are rejected when applicable.
- ID handling is correct.

Example:

```text
shouldUpdateExistingResult
shouldPreserveResultIdWhenUpdating
shouldThrowResourceNotFoundExceptionWhenUpdatingUnknownResult
shouldNotSaveWhenResultDoesNotExist
```

---

# 10. delete Tests

Test at minimum:

- Existing resource is deleted.
- Correct ID/entity is used.
- Unknown resource produces the expected behavior.
- Delete is not executed when lookup fails, if lookup is part of the service contract.
- Repository interactions are correct.
- Referential/business restrictions are handled when applicable.

Example:

```text
shouldDeleteExistingResult
shouldThrowResourceNotFoundExceptionWhenDeletingUnknownResult
shouldNotDeleteWhenResultDoesNotExist
```

---

# 11. Business Rule Tests

Every business rule implemented in a service must have tests.

For each business rule, test:

- Valid case.
- Invalid case.
- Boundary conditions.
- Correct exception.
- Correct exception message when it is part of the contract.
- No persistence occurs after validation failure.

Examples:

```text
duplicate match identifiers
invalid score values
forbidden state transitions
date restrictions
maximum/minimum values
immutable fields
resource ownership
dependency existence
```

When a new business rule is added, tests must be added in the same change.

---

# 12. Exception Tests

Every service exception path must be tested.

Use assertions such as:

```java
assertThatThrownBy(() -> service.findById(999L))
        .isInstanceOf(ResourceNotFoundException.class)
        .hasMessageContaining("Result");
```

Do not test only that an exception occurred.

Verify the correct exception type and meaningful message when appropriate.

---

# 13. Mockito Interaction Verification

Verify important interactions.

Examples:

```java
verify(repository).findById(id);
verify(repository).save(entity);
verify(mapper).toDto(entity);
verify(repository, never()).save(any());
verifyNoMoreInteractions(repository);
```

Do not over-specify irrelevant internal interactions.

Verify interactions that protect business behavior or make the test intent clearer.

---

# 14. Test Data

Create readable and reusable test fixtures/builders when the amount of test data grows.

Examples:

```text
ResultTestData
ResultFixture
ResultBuilder
```

Avoid unexplained magic values.

Prefer:

```java
private static final Long RESULT_ID = 1L;
private static final String MATCH_ID = "MATCH-2026-001";
```

---

# 15. Test Naming

Use descriptive English names.

Preferred style:

```java
@Test
void shouldReturnResultWhenIdExists() {
}
```

Avoid:

```java
@Test
void test1() {
}
```

The test name must describe expected behavior.

---

# 16. Arrange Act Assert

Service tests should follow a clear structure:

```text
Arrange
Act
Assert
```

Example:

```java
@Test
void shouldReturnResultWhenIdExists() {
    // Arrange
    when(repository.findById(RESULT_ID))
            .thenReturn(Optional.of(entity));

    when(mapper.toDto(entity))
            .thenReturn(dto);

    // Act
    ResultDTO result = service.findById(RESULT_ID);

    // Assert
    assertThat(result).isEqualTo(dto);
    verify(repository).findById(RESULT_ID);
    verify(mapper).toDto(entity);
}
```

Comments may be omitted when the structure is already obvious.

---

# 17. Cucumber HTML Report Is Mandatory

Every Cucumber execution must generate:

```text
target/cucumber-reports/cucumber.html
```

Also generate machine-readable reports:

```text
target/cucumber-reports/cucumber.json
target/cucumber-reports/cucumber.xml
```

Configure Cucumber with compatible plugins equivalent to:

```text
pretty
html:target/cucumber-reports/cucumber.html
json:target/cucumber-reports/cucumber.json
junit:target/cucumber-reports/cucumber.xml
```

Use configuration compatible with the actual Cucumber version in the project.

---

# 18. HTML Report Requirements

The Cucumber HTML report must clearly show:

- Feature names.
- Scenario names.
- Steps.
- Passed scenarios.
- Failed scenarios.
- Skipped scenarios.
- Failure messages.
- Execution duration.
- Enough diagnostic information to understand failures.

Expected file:

```text
target/cucumber-reports/cucumber.html
```

The report must be generated automatically when the Cucumber suite runs.

---

# 19. Service Test Report

Service unit tests must also produce standard Maven/JUnit reports.

Expected Maven Surefire output:

```text
target/surefire-reports/
```

The reports must contain results for every `*ServiceImplTest`.

Do not disable Surefire reporting.

---

# 20. Optional Unified HTML Test Report

When practical and dependency-compatible, generate an additional unified HTML report summarizing:

- Service unit tests.
- Cucumber API tests.
- Total tests.
- Passed tests.
- Failed tests.
- Skipped tests.

The unified report is optional.

The Cucumber HTML report remains mandatory.

Do not introduce unstable reporting plugins merely to create a unified report.

---

# 21. Maven Execution

All normal unit tests and Cucumber tests should run as part of the documented Maven test lifecycle.

Preferred command:

```bash
mvn clean test
```

If Cucumber integration tests intentionally run in a separate Maven phase, use:

```bash
mvn clean verify
```

and document why.

A failing service test or Cucumber scenario must fail the Maven build.

---

# 22. Required Execution Order for the Agent

After implementing or modifying an API:

1. Identify every service interface.
2. Identify every service implementation.
3. Identify every public service method.
4. Create/update the corresponding unit tests.
5. Cover successful paths.
6. Cover not-found paths.
7. Cover validation failures.
8. Cover business rules.
9. Cover meaningful boundaries.
10. Verify important Mockito interactions.
11. Run service unit tests.
12. Fix all failures.
13. Run Cucumber API tests.
14. Fix all failures.
15. Generate the Cucumber HTML report.
16. Verify the HTML report exists.
17. Verify Surefire reports exist.
18. Run the complete Maven build.
19. Do not consider the task complete until the build succeeds.

---

# 23. Coverage Expectations

Aim for strong service-layer branch and behavior coverage.

Do not create meaningless tests solely to increase a percentage.

Prioritize:

- Every public method.
- Every business branch.
- Every exception path.
- Every validation branch.
- Important boundary cases.
- Repository interaction behavior.
- Mapper interaction behavior.

If JaCoCo is configured in the project, service coverage should be included in its report.

Do not claim 100% coverage unless the generated coverage report actually proves it.

---

# 24. Optional JaCoCo Integration

When requested or already used by the project, configure JaCoCo to generate:

```text
target/site/jacoco/index.html
```

The report should include service implementation classes.

JaCoCo coverage is complementary to Cucumber reporting.

Cucumber reports behavior scenarios.
JaCoCo reports executed code coverage.
Surefire reports JUnit test execution.

---

# 25. Final Test Summary

After running tests, provide a clear summary such as:

```text
Test Summary

Service unit tests:
Passed: 35
Failed: 0
Skipped: 0

Cucumber scenarios:
Passed: 24
Failed: 0
Skipped: 0

Reports:

Cucumber:
target/cucumber-reports/cucumber.html

JUnit / Surefire:
target/surefire-reports/

JaCoCo (if configured):
target/site/jacoco/index.html
```

Never invent test counts.

Use actual execution results.

---

# 26. Completion Criteria

Testing is complete only when:

- Every service implementation has a test class.
- Every public service method is tested.
- Successful service paths are tested.
- Failure paths are tested.
- Not-found behavior is tested.
- Business rules are tested.
- Important boundaries are tested.
- Mockito collaborators are correctly isolated.
- Cucumber endpoint tests pass.
- Service unit tests pass.
- Maven build succeeds.
- Cucumber HTML report exists.
- Cucumber JSON/XML reports exist.
- Surefire reports exist.
- No secrets appear in test output or reports.
- All tests and documentation are in English.

---

# 27. Priority

When used together:

- `CRUD_INSTRUCTIONS.md` defines architecture and CRUD implementation.
- `ENGLISH_PROJECT_INSTRUCTIONS.md` defines English-only conventions.
- `CUCUMBER_API_TESTING_INSTRUCTIONS.md` defines endpoint acceptance testing.
- `SWAGGER_OPENAPI_INSTRUCTIONS.md` defines API documentation.
- This file defines comprehensive service unit testing and mandatory Cucumber HTML reporting.

All instruction files must be respected before the project is considered complete.
