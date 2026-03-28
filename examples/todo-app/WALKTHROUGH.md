# Todo App SDD Workflow Walkthrough

This document shows the step-by-step process of building the Todo CRUD feature using Specification-Driven Development.

## Phase 1: Project Setup

### Step 1: Create Constitution

**Command:** `/speckit.constitution`

**Process:**
1. Decided constitution needed (team project, patterns emerging)
2. Identified common patterns:
   - RESTful API design
   - Error response format (422 for validation)
   - Validation approach
   - Testing standards
3. Created `.specify/memory/constitution.md`
4. Committed to git

**Output:** `.specify/memory/constitution.md`

**Key Decisions:**
- Use 422 for validation errors (not 400)
- UUIDs for IDs (not auto-increment)
- Standard error response format

---

## Phase 2: Feature Specification

### Step 2: Create Feature Spec

**Command:** `/spex:spec` (clear requirements, skipped brainstorming)

**Input:**
```
I need a REST API for todo CRUD operations:
- Create, read, update, delete todos
- Todos have: title, description, completed, due_date
- Validate input (title required, description optional)
- Standard REST endpoints
```

**Process:**
1. Extracted requirements from input
2. Checked constitution for API patterns
3. Created spec following constitution format
4. Added error cases and edge cases
5. Defined success criteria

**Output:** `specs/features/todo-crud.md`

**Coverage:**
- 6 functional requirements
- 3 error types (validation, not found, server)
- 7 edge cases
- Request/response examples

### Step 3: Review Spec for Soundness

**Command:** (Automatic via `/spex:spec`, or manual `/spex:review-spec`)

**Checks:**
- ✓ All sections complete
- ✓ No ambiguous language
- ✓ Can generate implementation plan
- ✓ Success criteria measurable
- ✓ Aligns with constitution

**Result:** ✅ SOUND - Ready for implementation

---

## Phase 3: Implementation

### Step 4: Generate Implementation Plan

**Command:** `/spex:implement` → calls `/spex:writing-plans`

**Process:**
1. Read spec completely
2. Extracted all requirements
3. Identified files needed:
   - `src/api/todos.js` - Route handlers
   - `src/models/todo.js` - Todo model
   - `src/middleware/validation.js` - Validation
   - `tests/api/todos.test.js` - Tests
4. Created tasks for each requirement
5. Mapped requirements to tests

**Output:** `docs/plans/2025-11-10-todo-crud-implementation.md`

**Plan Structure:**
- Requirements coverage (each spec req → tasks)
- Error handling implementation
- Edge case handling
- Test strategy
- File organization

### Step 5: Implement with TDD

**Command:** (Automatic via `/spex:implement`, uses `test-driven-development`)

**For each requirement:**

**Example: Requirement 1 - List all todos**

1. **Write test first:**
```javascript
test('GET /api/todos should return all todos', async () => {
  // Arrange
  await createTestTodo({ title: 'Test 1' });
  await createTestTodo({ title: 'Test 2' });

  // Act
  const response = await request(app).get('/api/todos');

  // Assert
  expect(response.status).toBe(200);
  expect(response.body).toHaveLength(2);
  expect(response.body[0].title).toBe('Test 2'); // newest first
});
```

2. **Watch it fail:** ❌ (endpoint doesn't exist)

3. **Write minimal code:**
```javascript
router.get('/todos', async (req, res) => {
  const todos = await Todo.findAll({
    order: [['created_at', 'DESC']]
  });
  res.json(todos);
});
```

4. **Watch it pass:** ✅

5. **Refactor:** Clean up, extract logic if needed

6. **Check spec compliance:**
   - ✓ Endpoint path matches spec: GET /api/todos
   - ✓ Returns array of todos
   - ✓ Sorted by created_at descending

**Repeat for all 6 functional requirements...**

### Step 6: Code Review Against Spec

**Command:** `/spex:review-code`

**Review Process:**
1. Load spec: `specs/features/todo-crud.md`
2. Check each requirement against code
3. Calculate compliance score

**Results:**
```
Compliance Summary:
- Functional Requirements: 6/6 (100%)
- Error Handling: 3/3 (100%)
- Edge Cases: 7/7 (100%)

Overall: 100% ✅

Deviations: None
Extra Features: None

Recommendation: Proceed to verification
```

### Step 7: Verification

**Command:** `/spex:verification-before-completion`

**Verification Steps:**

1. **Run tests:**
```bash
$ npm test

✅ All tests passing (42/42)
✅ Coverage: 94%
```

2. **Validate spec compliance:**
```
Checking requirements against spec...
✓ Requirement 1: List todos - Implemented & tested
✓ Requirement 2: Create todo - Implemented & tested
✓ Requirement 3: Get single todo - Implemented & tested
✓ Requirement 4: Update todo - Implemented & tested
✓ Requirement 5: Delete todo - Implemented & tested
✓ Requirement 6: Mark complete - Implemented & tested

Spec Compliance: 100% ✅
```

3. **Check spec drift:**
```
Comparing spec to implementation...
No drift detected ✅
```

4. **Verify success criteria:**
```
From spec:
✓ All CRUD operations work correctly
✓ All validation rules enforced
✓ All error cases handled properly
✓ All endpoints return correct status codes
✓ Performance requirements met
✓ 100% test coverage

All criteria met ✅
```

**Result:** ✅ VERIFIED - Ready for completion

---

## Phase 4: Spec Evolution (Hypothetical)

### Scenario: Implementation Reveals Better Approach

**During implementation, discovered:**
- Adding `updated_at` timestamp would be helpful
- Spec doesn't mention it

**Command:** `/spex:evolve`

**Process:**

1. **Detect mismatch:**
```
Spec says: Return id, title, description, completed, created_at
Code returns: (above) + updated_at
```

2. **Analyze:**
- Type: Minor addition (non-breaking)
- Severity: Minor
- Impact: Helpful addition, no breaking change

3. **Recommend:**
```
Option: Update Spec

Reasoning:
- updated_at is standard practice
- Helpful for clients
- Non-breaking addition
- Implementation is better than spec

User config: auto_update_spec.threshold = "minor"

Action: Auto-updating spec...
```

4. **Execute:**
- Updated spec to include `updated_at` in response
- Added to spec changelog
- Re-verified compliance: 100% ✅

---

## Key Observations

### What Worked Well

1. **Constitution prevented bike-shedding**
   - Error format already decided
   - Validation approach standardized
   - Testing patterns established

2. **Spec made implementation straightforward**
   - Clear requirements
   - All error cases defined
   - Examples provided

3. **TDD caught bugs early**
   - Edge cases discovered during test writing
   - Validation logic tested before implementation

4. **Spec compliance checking prevented drift**
   - Implementation stayed aligned with spec
   - No feature creep
   - Clear success criteria

### Workflow Efficiency

**Time breakdown:**
- Constitution: 30 min (one-time investment)
- Spec creation: 20 min
- Spec review: 5 min
- Implementation plan: 10 min
- TDD implementation: 2 hours
- Code review: 10 min
- Verification: 5 min

**Total:** ~3 hours (including constitution)

**Without SDD:** Estimated 4-5 hours with:
- More back-and-forth on requirements
- Edge cases discovered late
- Inconsistent error handling
- Post-hoc documentation
- Likely spec drift

**Savings:** 1-2 hours + higher quality

### Lessons Learned

1. **Spec review saves time**
   - 5 minutes reviewing spec prevented 30 minutes of rework

2. **Constitution provides velocity**
   - Not re-deciding error formats for each endpoint
   - Consistent patterns across features

3. **TDD + Spec = High confidence**
   - Tests validate spec requirements
   - Spec ensures complete coverage
   - Combined: very high quality

4. **Evolution is normal**
   - Specs will change
   - Having process for it prevents drift
   - Auto-updates work well for minor changes

## Conclusion

Specification-Driven Development with SDD provides:
- **Clarity** through formal specs
- **Consistency** through constitution
- **Quality** through TDD and verification
- **Maintainability** through spec compliance

The workflow overhead is minimal compared to the time saved preventing rework and the quality improvements achieved.
