---
name: pagination-filtering
description: Make the listing endpoint of a CRUD API paginated and filterable by every entity field, via a dynamic Specification and a Pageable-aware controller.
---

# pagination-filtering

Turns a bare `GET /api/<entities>` that returns every row as a JSON array
into a paginated, filterable listing endpoint — the default a real API
needs, not something bolted on later. Apply this immediately after the
`crud` skill, before writing tests for the listing endpoint.

These instructions must be followed together with `crud`, `english-javadoc`,
`swagger-openapi`, and `service-testing`.

## 1. Filter DTO

One class per entity, one optional field per entity field (Lombok
`@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder`, `@Schema`
descriptions for Swagger). Every field is nullable/optional — unset means
"don't filter on this".

```java
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class <Entity>Filter {
    private Long id;               // exact
    private String someTextField;  // partial, case-insensitive
    private Integer someNumber;    // exact
    private LocalDate someDate;    // exact
}
```

## 2. Dynamic Specification

One `<Entity>Specifications` utility class building a `Specification<Entity>`
from the filter: exact match (`criteriaBuilder.equal`) for id/numeric/date
fields, case-insensitive partial match (`criteriaBuilder.like(lower(path),
"%value%")`) for string fields, combined with AND, skipping any field left
null/blank.

```java
public static Specification<Entity> fromFilter(EntityFilter filter) {
    return (root, query, cb) -> {
        List<Predicate> predicates = new ArrayList<>();
        if (filter.getId() != null) predicates.add(cb.equal(root.get("id"), filter.getId()));
        // ... one branch per field, string fields via a shared containsIgnoreCase helper
        return cb.and(predicates.toArray(new Predicate[0]));
    };
}
```

## 3. Repository, service, controller

- Repository: extend `JpaSpecificationExecutor<Entity>` alongside `JpaRepository`.
- Service: `findAll(EntityFilter filter, Pageable pageable)` returns
  `Page<EntityResponseDTO>` — build the `Specification`, call
  `repository.findAll(specification, pageable).map(mapper::toResponseDTO)`.
  Give it English JavaDoc (see `english-javadoc`).
- Controller: bind both the filter and the pageable as query params via
  springdoc's `@ParameterObject` (`org.springdoc.core.annotations.ParameterObject`
  — springdoc-openapi resolves `Pageable` into `page`/`size`/`sort` params
  natively, no extra config needed), default page size via
  `@PageableDefault(size = 20, sort = "id")`. Wrap the result in
  `org.springframework.data.web.PagedModel<EntityResponseDTO>` before
  returning — **do not** return a bare `Page<T>` (Spring emits a
  "serializing PageImpl instances as-is is not supported" warning and the
  JSON shape is undocumented); `PagedModel` needs no extra dependency
  (it lives in spring-data-commons, not spring-hateoas) and produces a
  stable `{ "content": [...], "page": { "size", "number", "totalElements",
  "totalPages" } }` envelope.

```java
@GetMapping
public ResponseEntity<PagedModel<EntityResponseDTO>> findAll(
        @ParameterObject EntityFilter filter,
        @ParameterObject @PageableDefault(size = 20, sort = "id") Pageable pageable) {
    Page<EntityResponseDTO> page = service.findAll(filter, pageable);
    return ResponseEntity.ok(new PagedModel<>(page));
}
```

## 4. This is a breaking response-shape change

If a listing endpoint already existed as a bare array, every consumer
breaks: update Cucumber steps/scenarios and any client code that assumed
`$` was the array root — it's now `content`. Grep for "should be an array"
style assertions and repoint them at `content`.

## 5. Tests

- **`<Entity>SpecificationsTest`** (`@DataJpaTest`, real H2, no mocks): one
  test per field proving it filters correctly, plus combined-filter and
  no-match cases. This is the only reliable way to verify dynamic Criteria
  logic — a mocked repository can't catch a wrong `criteriaBuilder` call.
- **Service test**: update the existing `findAll` tests to the new
  `(filter, pageable)` signature; mock
  `repository.findAll(any(Specification.class), eq(pageable))` returning a
  `PageImpl<>(...)`. Don't try to verify the Specification's *content*
  here — that's `<Entity>SpecificationsTest`'s job; just verify delegation
  and mapping.
- **Cucumber**: a handful of scenarios — one filter per representative
  field type (string partial match, exact numeric/date match, combined
  filters, a filter matching nothing), plus one pagination scenario
  (`page`/`size` smaller than the total, asserting `page.totalElements`).
  Reuse the existing generic HTTP steps; nested JSON paths like
  `content[0].someField` and `page.totalElements` work out of the box with
  RestAssured's JsonPath — no new step definitions needed for that.

## Verify, don't claim

Hit the live endpoint with combinations of filters and pagination params
and read the actual JSON back before calling this done:

```bash
curl "http://localhost:8080/api/<entities>?someTextField=partial&page=0&size=5"
```

Confirm `content` has the expected rows and `page.totalElements` matches
reality — not just that the endpoint returns 200.
