# Todo App Project Constitution

**Project:** Todo App Example
**Created:** 2025-11-10
**Last Updated:** 2025-11-10

## Purpose

This constitution defines project-wide principles, patterns, and standards for the Todo App.
All features and implementations must align with these principles.

## Architectural Principles

### RESTful API Design
All API endpoints follow REST conventions with standard HTTP methods and resource-oriented URLs.

**Pattern:**
- `GET /api/todos` - List resources
- `POST /api/todos` - Create resource
- `PUT /api/todos/:id` - Update resource
- `DELETE /api/todos/:id` - Delete resource

**Examples:**
- ✓ `GET /api/todos` - Good (plural, noun)
- ✗ `GET /api/getTodos` - Bad (verb in URL)
- ✓ `PUT /api/todos/123` - Good (resource ID in path)
- ✗ `POST /api/todos/update` - Bad (action in path)

### Data Validation
Validate all input on the server. Never trust client input.

**Approach:**
- Validate before any business logic
- Return 422 for validation failures
- Provide specific field-level error messages

## API Design Standards

### HTTP Methods
- `GET` - Retrieve resources (safe, idempotent)
- `POST` - Create new resources
- `PUT` - Update existing resources (idempotent)
- `DELETE` - Remove resources (idempotent)

### HTTP Status Codes
- `200 OK` - Successful request
- `201 Created` - Resource created successfully
- `204 No Content` - Successful with no response body
- `400 Bad Request` - Malformed request
- `401 Unauthorized` - Authentication required
- `404 Not Found` - Resource doesn't exist
- `422 Unprocessable Entity` - Validation failed
- `500 Internal Server Error` - Server error

### Request/Response Format
- **Content-Type:** `application/json`
- **Character Encoding:** UTF-8
- **Date Format:** ISO 8601 (YYYY-MM-DDTHH:mm:ssZ)

## Error Handling

### Error Response Format
All errors return consistent JSON format:

```json
{
  "error": "Human-readable error message",
  "field": "field_name",  // for validation errors
  "code": "ERROR_CODE"    // optional error code
}
```

**Examples:**
```json
{
  "error": "Title is required",
  "field": "title",
  "code": "VALIDATION_ERROR"
}
```

### Common Error Scenarios

**Validation Failure:**
- Status: 422
- Include field name
- Specific error message

**Resource Not Found:**
- Status: 404
- Generic message (no details about existence)

**Server Error:**
- Status: 500
- Log full error server-side
- Return generic message to client

## Validation Standards

### Field Validation
- **Required fields:** Explicitly validate and error
- **String lengths:** Min/max lengths specified
- **Formats:** Email, URL, etc. validated with standard patterns
- **Enums:** Validate against allowed values

### Todo-Specific Validation
- **Title:** Required, 1-200 characters
- **Description:** Optional, max 2000 characters
- **Completed:** Boolean, defaults to false
- **Due Date:** Optional, ISO 8601 format, not in past

## Testing Standards

### Coverage Requirements
- Minimum 80% code coverage
- 100% coverage for API endpoints
- All error cases must have tests

### Test Organization
```
tests/
  ├── api/
  │   └── todos.test.js       # API endpoint tests
  ├── models/
  │   └── todo.test.js        # Model tests
  └── middleware/
      └── validation.test.js  # Validation tests
```

### Test Types Required
- **Unit tests:** For all functions/methods
- **Integration tests:** For all API endpoints
- **Edge case tests:** For boundary conditions

### Test Naming Convention
Format: `[method] [endpoint/function] [should] [expected behavior]`

Examples:
- `GET /api/todos should return all todos`
- `POST /api/todos should create a new todo`
- `PUT /api/todos/:id should return 404 when todo not found`

## Code Quality Standards

### JavaScript Style
- **Naming:**
  - camelCase for variables and functions
  - PascalCase for classes
  - UPPER_SNAKE_CASE for constants
- **Formatting:** Use Prettier
- **Linting:** Use ESLint with recommended config

### Code Organization
```
src/
  ├── api/        # Route handlers
  ├── models/     # Data models
  ├── middleware/ # Express middleware
  └── utils/      # Helper functions
```

### Documentation
- JSDoc for public functions
- Inline comments for complex logic only
- README in each major directory

## Database Standards

### Schema Design
- Use migrations for schema changes
- Include timestamps (created_at, updated_at)
- Use UUIDs for IDs (not auto-increment)

### Queries
- Parameterized queries only (prevent SQL injection)
- Index commonly queried fields
- Limit result sets (pagination)

## Security Requirements

### Input Sanitization
- Escape HTML in all user input
- Validate all input against expected format
- Reject unexpected fields

### Error Messages
- Never expose internal details in errors
- Don't reveal whether resource exists (404 generic)
- Log sensitive errors server-side only

## Performance Requirements

### Response Times
- API responses: < 200ms (p95)
- Database queries: < 50ms (p95)

### Pagination
- Default page size: 50 items
- Max page size: 100 items
- Use offset-based pagination

## Change Management

### Updating This Constitution
- Changes require rationale
- Document in Decision Log below
- Communicate changes

### Exceptions
- Exceptions documented in feature spec
- Requires justification
- Reviewed in code review

## Decision Log

### 2025-11-10: Use Express.js
**Context:** Need web framework for API
**Decision:** Use Express.js
**Rationale:** Industry standard, good middleware ecosystem, well-documented
**Implications:** Middleware-based architecture, standard route patterns

### 2025-11-10: Use UUIDs for IDs
**Context:** Need ID strategy for todos
**Decision:** Use UUIDs instead of auto-increment integers
**Rationale:** Better for distributed systems, no enumeration attacks
**Implications:** IDs are strings not numbers, slightly larger storage

### 2025-11-10: Validation Returns 422
**Context:** Need consistent validation error status
**Decision:** Use 422 Unprocessable Entity for validation failures
**Rationale:** Semantically correct (syntax is valid, semantics are not)
**Implications:** Different from 400 Bad Request (syntax errors)
