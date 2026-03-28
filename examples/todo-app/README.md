# Todo App Example - Complete Spex Workflow

This example demonstrates the complete Specification-Driven Development (SDD) workflow using spex.

## What This Example Shows

1. **Creating a constitution** - Project-wide principles
2. **Brainstorming a feature** - From rough idea to spec
3. **Creating a spec** - Formal specification
4. **Reviewing the spec** - Soundness validation
5. **Generating implementation plan** - From spec to tasks
6. **Implementing with TDD** - Test-first development
7. **Spec compliance checking** - Validation against spec
8. **Handling spec evolution** - Reconciling mismatches

## Files in This Example

```
todo-app/
├── README.md                           # This file
├── WALKTHROUGH.md                      # Step-by-step workflow guide
├── .specify/
│   └── memory/
│       └── constitution.md             # Project constitution
├── specs/
│   └── features/
│       └── todo-crud.md                # Todo CRUD feature spec
├── docs/
│   └── plans/
│       └── 2025-11-10-todo-crud-implementation.md
├── src/
│   ├── api/
│   │   └── todos.js                    # API implementation
│   ├── models/
│   │   └── todo.js                     # Todo model
│   └── middleware/
│       └── validation.js               # Validation middleware
└── tests/
    └── api/
        └── todos.test.js               # API tests
```

## The Feature

A simple Todo API with CRUD operations:
- Create todo
- List todos
- Update todo
- Delete todo
- Mark todo as complete

## Workflow Overview

### Phase 1: Project Setup
1. Create constitution defining project standards
2. Establish patterns for API design, error handling, testing

### Phase 2: Feature Specification
1. Brainstorm the todo CRUD feature
2. Create formal specification
3. Review spec for soundness

### Phase 3: Implementation
1. Generate implementation plan from spec
2. Implement using TDD (test-first)
3. Verify spec compliance

### Phase 4: Evolution (When Needed)
1. Detect spec/code mismatch
2. AI analysis and recommendation
3. Update spec or fix code
4. Re-verify compliance

## How to Use This Example

### Option 1: Read Through
Simply read the files in order to understand the workflow:
1. `.specify/memory/constitution.md` - See project principles
2. `specs/features/todo-crud.md` - See feature spec
3. `docs/plans/2025-11-10-todo-crud-implementation.md` - See implementation plan
4. `src/` and `tests/` - See implementation and tests
5. `WALKTHROUGH.md` - See step-by-step process

### Option 2: Follow Along
Use this example as a template for your own project:
1. Copy the constitution and adapt it
2. Follow the spec structure for your features
3. Use the plan format for your implementations
4. Apply the same workflow to your code

### Option 3: Interactive Exploration
Start Claude Code in this directory and ask questions:
- "Explain how the spec maps to the implementation"
- "Show me the spec compliance validation"
- "What would happen if I add a new field to the API?"

## Key Takeaways

### 1. Constitution Provides Consistency
See how `.specify/memory/constitution.md` defines:
- RESTful API patterns
- Error response format
- Validation approach
- Testing standards

All specs and code follow these patterns.

### 2. Spec is Source of Truth
The implementation in `src/api/todos.js` directly implements requirements from `specs/features/todo-crud.md`:
- Each endpoint matches spec
- Error handling matches spec
- Validation matches spec

### 3. Plan Bridges Spec to Code
`docs/plans/2025-11-10-todo-crud-implementation.md` shows how spec requirements become concrete tasks with file paths and test strategies.

### 4. Tests Validate Spec
Tests in `tests/api/todos.test.js` verify spec requirements:
- Each requirement has tests
- Each error case has tests
- Each edge case has tests

### 5. Evolution is Normal
The `WALKTHROUGH.md` shows how specs evolve when implementation reveals better approaches.

## Running the Example

This is a demonstration example, not a runnable application. The code shows structure and patterns, not a complete implementation.

To see a runnable version, you would need to:
1. Add dependencies (`package.json`)
2. Add database setup
3. Add server configuration
4. Complete all TODO items in the code

## Questions This Example Answers

**Q: How detailed should a spec be?**
A: See `specs/features/todo-crud.md` - specific enough to implement, not prescribing implementation details.

**Q: How do I organize requirements?**
A: See the spec structure - functional, error handling, edge cases, success criteria.

**Q: What goes in a constitution?**
A: See `.specify/memory/constitution.md` - patterns that repeat across features.

**Q: How do I plan from a spec?**
A: See the implementation plan - each spec requirement becomes tasks with file paths.

**Q: What does spec-compliant code look like?**
A: See `src/api/todos.js` - each endpoint matches spec, error codes match, validation matches.

**Q: How do I test spec requirements?**
A: See `tests/api/todos.test.js` - test names reference spec requirements, all cases covered.

## Next Steps

After understanding this example:

1. **Try it yourself**: Create a small feature using this workflow
2. **Adapt the templates**: Use the constitution and spec as starting points
3. **Practice the skills**: Use `/spex:brainstorm`, `/spex:spec`, `/spex:implement`
4. **Experience evolution**: When code diverges from spec, use `/spex:evolve`

## Resources

- Full spex documentation: `../../README.md`
- Skill reference: `../../spex/skills/`
- Design documentation: `../../docs/design.md`
