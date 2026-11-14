---
name: english-javadoc
description: Add English JavaDoc (purpose, @param, @return, @throws) to every method declared in an interface.
---

## Interface Method Documentation

Every method declared in an interface must include JavaDoc explaining its purpose.

The documentation must always be written in English.

The JavaDoc should explain:

- What the method does.
- The meaning of its parameters using `@param`.
- The returned value using `@return`, when applicable.
- Relevant exceptions using `@throws`, when applicable.

Example:

```java
public interface ResultService {

    /**
     * Retrieves all available results.
     *
     * @return a list containing all results
     */
    List<ResultDTO> findAll();

    /**
     * Retrieves a result by its unique identifier.
     *
     * @param id the unique identifier of the result
     * @return the result associated with the specified identifier
     * @throws ResourceNotFoundException if no result exists with the specified identifier
     */
    ResultDTO findById(Long id);

    /**
     * Creates and persists a new result.
     *
     * @param resultDTO the data of the result to create
     * @return the newly created result
     */
    ResultDTO create(ResultDTO resultDTO);

    /**
     * Updates an existing result.
     *
     * @param id the unique identifier of the result to update
     * @param resultDTO the new data for the result
     * @return the updated result
     * @throws ResourceNotFoundException if no result exists with the specified identifier
     */
    ResultDTO update(Long id, ResultDTO resultDTO);

    /**
     * Deletes a result by its unique identifier.
     *
     * @param id the unique identifier of the result to delete
     * @throws ResourceNotFoundException if no result exists with the specified identifier
     */
    void delete(Long id);
}