---
name: crud
description: Scaffold the layered CRUD architecture (controller/dto/mapper/model/repository/service) for a REST API entity in this project.
---

# Instrucciones para APIs REST CRUD

Cuando se solicite crear una API CRUD en este proyecto, seguir estas reglas.

## Stack
- Java 17
- Spring Boot
- Maven
- Spring Web
- Spring Data JPA
- H2
- MapStruct

## Arquitectura
Crear las capas:
- controller
- dto
- mapper
- model
- repository
- service
- service/impl
- exception

## Entity
Toda entidad debe tener una clave primaria autogenerada:

```java
@Id
@GeneratedValue(strategy = GenerationType.IDENTITY)
private Long id;
```

## Service
Crear siempre:
- `EntityService.java` como interfaz.
- `EntityServiceImpl.java` como implementación.

El Controller debe depender de la interfaz, nunca directamente de la implementación.

## Repository
Crear una interfaz que extienda `JpaRepository<Entity, Long>`.

## DTO
No exponer directamente las entidades desde el Controller.
Usar DTO para entrada y salida.

## Mapper
Usar MapStruct con `componentModel = "spring"` para convertir Entity <-> DTO.

## Controller
Implementar como mínimo:
- GET todos
- GET por ID
- POST
- PUT
- DELETE

Usar `ResponseEntity`.
- POST: HTTP 201
- DELETE: HTTP 204
- Recurso inexistente: HTTP 404

## Dependencias
Usar inyección por constructor.
No usar `@Autowired` sobre atributos.

## Flujo
Controller -> Service Interface -> ServiceImpl -> Repository -> Database

## Regla final
Cuando se solicite una nueva API, crear físicamente todos los archivos necesarios,
mantener esta arquitectura y comprobar que el proyecto compile.
