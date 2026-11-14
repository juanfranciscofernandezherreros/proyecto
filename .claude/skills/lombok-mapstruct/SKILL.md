---
name: lombok-mapstruct
description: Wire Lombok and MapStruct consistently across entities/DTOs to remove boilerplate and keep entity<->DTO mapping explicit.
---

# Lombok and MapStruct Instructions

## Objective

All Java CRUD APIs in this project must use Lombok and MapStruct consistently to reduce boilerplate and keep mapping logic explicit and maintainable.

These instructions must be followed together with the rest of the project instruction files.

All source code, comments, Javadocs, examples, generated documentation, and test names must be written in English.

---

## 1. Lombok Is Mandatory

Use Lombok for DTOs, entities, configuration models, request/response models, builders, and other plain data-holder classes when appropriate.

Preferred annotations include:

```java
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
```

Use:

```java
@Data
```

only when all generated methods are actually desired.

Avoid blindly using `@Data` on JPA entities.

---

## 2. JPA Entity Rules

For JPA entities, prefer:

```java
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Entity
public class Result {
}
```

Do not use Lombok-generated `equals`, `hashCode`, or `toString` carelessly on JPA entities with lazy relationships.

Avoid:

```java
@Data
@Entity
public class Result {
}
```

when the entity contains relationships or when generated equality semantics may cause problems.

For relationships, use exclusions where required:

```java
@ToString.Exclude
@EqualsAndHashCode.Exclude
```

---

## 3. Generated ID

Server-generated identifiers must remain read-only from the API perspective where applicable.

Example:

```java
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;
```

Do not manually assign generated IDs during create operations unless the business requirement explicitly demands it.

---

## 4. DTO Rules

DTOs should use Lombok to remove boilerplate.

Example:

```java
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ResultDTO {

    private Long id;
    private String matchId;
    private String homeTeam;
    private String awayTeam;
}
```

If immutability is desired, prefer an immutable DTO design and compatible Lombok annotations.

---

## 5. Constructor Injection

Use constructor injection.

Prefer Lombok:

```java
@RequiredArgsConstructor
@Service
public class ResultServiceImpl implements ResultService {

    private final ResultRepository repository;
    private final ResultMapper mapper;
}
```

Avoid field injection:

```java
@Autowired
private ResultRepository repository;
```

---

## 6. MapStruct Is Mandatory

Use MapStruct for conversion between API models and persistence/domain models.

Do not write repetitive manual mapping logic when MapStruct can perform it safely.

Recommended mapper:

```java
@Mapper(componentModel = "spring")
public interface ResultMapper {

    ResultDTO toDto(Result entity);

    Result toEntity(ResultDTO dto);
}
```

---

## 7. Mapper Naming Convention

Use:

```text
ResultMapper
UserMapper
MatchMapper
```

Mapper interfaces must be located in:

```text
mapper/
```

---

## 8. Mapper Javadocs

Every public mapper method must include English JavaDoc.

Example:

```java
/**
 * Converts a Result entity into a ResultDTO.
 *
 * @param entity the entity to convert
 * @return the mapped DTO
 */
ResultDTO toDto(Result entity);
```

---

## 9. Update Mapping

For update operations, prefer MapStruct update methods using `@MappingTarget`.

Example:

```java
/**
 * Updates an existing Result entity with values from the DTO.
 *
 * @param dto the source data
 * @param entity the entity to update
 */
void updateEntity(ResultDTO dto, @MappingTarget Result entity);
```

Do not manually copy field after field in the service when MapStruct can handle the update.

---

## 10. Ignore Generated IDs on Create

When appropriate, prevent client-provided IDs from overwriting server-generated IDs.

Example:

```java
@Mapping(target = "id", ignore = true)
Result toEntity(ResultDTO dto);
```

If separate request and response DTOs are used, prefer omitting the ID from the create request model entirely.

---

## 11. Null Handling

Define update semantics explicitly.

For PATCH-like behavior, use:

```java
@BeanMapping(nullValuePropertyMappingStrategy = NullValuePropertyMappingStrategy.IGNORE)
void partialUpdate(ResultDTO dto, @MappingTarget Result entity);
```

Do not use null-ignoring behavior for PUT unless the API contract explicitly defines it that way.

---

## 12. Nested Mapping

Use MapStruct for nested mappings where reasonable.

Example:

```java
@Mapping(source = "team.name", target = "teamName")
ResultDTO toDto(Result entity);
```

Avoid leaking JPA entities directly into API DTOs.

---

## 13. Collections

MapStruct should handle collections where possible.

Example:

```java
List<ResultDTO> toDtoList(List<Result> entities);
```

Prefer mapper collection methods over repeating stream mapping in multiple services.

---

## 14. Custom Mapping

Use qualified mapping methods only when needed.

Examples:

```java
@Named
default String normalizeName(String value) {
    return value == null ? null : value.trim();
}
```

Keep business logic out of mappers.

Mappers transform data; services implement business rules.

---

## 15. Lombok and MapStruct Compatibility

The Maven build must configure annotation processing correctly for both Lombok and MapStruct.

The project must include the required annotation processors.

The build must compile successfully from a clean checkout with:

```bash
mvn clean test
```

or:

```bash
mvn clean verify
```

---

## 16. Maven Configuration

Ensure the Maven compiler plugin includes compatible annotation processors.

Typical structure:

```xml
<annotationProcessorPaths>
    <path>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <version>${lombok.version}</version>
    </path>
    <path>
        <groupId>org.mapstruct</groupId>
        <artifactId>mapstruct-processor</artifactId>
        <version>${mapstruct.version}</version>
    </path>
</annotationProcessorPaths>
```

If the project requires the Lombok/MapStruct binding artifact for compatibility, include it.

Use versions compatible with the Java and Spring Boot versions used by the project.

---

## 17. No Manual Boilerplate

Do not manually create getters, setters, constructors, builders, or mapping code when Lombok or MapStruct is already responsible for them.

Avoid duplicate generated and manual methods.

---

## 18. Testing

Service tests should mock mapper dependencies when testing service behavior in isolation.

Mapper tests should verify custom or non-trivial mappings.

Simple auto-generated one-to-one mappings do not require exhaustive tests unless project policy requires them.

Always test:

- ignored fields
- custom mappings
- nested mappings
- update mappings
- null-handling behavior
- enum conversions
- date/time conversions
- field renames

---

## 19. Final Verification

Before considering the task complete:

- Lombok is configured.
- MapStruct is configured.
- Annotation processing works.
- No duplicate manual getters/setters exist.
- No unnecessary manual mapper code exists.
- Mapper interfaces are Spring components.
- Update mapping is handled correctly.
- Generated IDs are protected.
- JPA entities avoid unsafe Lombok usage.
- Maven build succeeds.
- Tests pass.

---

## Priority

This file defines Lombok and MapStruct conventions.

If another instruction file conflicts with this one, preserve architectural correctness and generated-ID safety, and prefer constructor injection and explicit mapping rules.
