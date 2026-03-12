---
name: constitution
description: Create and manage project constitution - defines project-wide principles, patterns, and standards that guide all specs and implementations
---

# Project Constitution Management

## Overview

Create and maintain a project constitution that defines project-wide principles, standards, and patterns.

A constitution provides:
- Architectural decisions
- Coding standards
- Error handling patterns
- Quality gates
- Common practices

All specs are validated against the constitution for consistency.

## Prerequisites

Ensure spec-kit is initialized:

{Skill: spec-kit}

If spec-kit prompts for restart, pause this workflow and resume after restart.

## What is a Constitution?

**Purpose:**
Document project-wide rules that ensure consistency across features.

**Contains:**
- Architectural principles
- Coding standards
- API design patterns
- Error handling approaches
- Security requirements
- Testing standards
- Performance requirements
- Accessibility standards

**Benefits:**
- Consistency across features
- Onboarding documentation
- Design decision record
- Spec validation reference

## When to Create

**Good times:**
- New project starting
- After second or third feature (patterns emerging)
- Team wants consistency
- Before major expansion

**Bad times:**
- First feature (too early, no patterns yet)
- During active implementation
- As reaction to single issue

**Rule of thumb:** Create after you see patterns repeating.

## The Process

### 1. Decide if Constitution Needed

**Ask:**
- Are there repeated patterns in specs?
- Do you want consistency enforced?
- Is this a team project?
- Is this a long-term project?

**If solo + small project:** Constitution might be overkill

**If team OR large OR long-term:** Constitution recommended

### 2. Gather Existing Patterns

**Review existing specs:**
```bash
ls specs/features/
cat specs/features/*.md
```

**Identify patterns:**
- How do we handle errors?
- What API patterns do we follow?
- What security requirements are common?
- What coding standards do we use?

**Extract commonalities:**
Make implicit standards explicit.

### 3. Use /speckit.constitution or Manual Creation

**With /speckit.constitution (if available):**
Invoke `/speckit.constitution` to create the constitution interactively.

The command writes to `.specify/memory/constitution.md`, which is the canonical location (matching upstream spec-kit).

**Manual creation (if command not available):**
Create `.specify/memory/constitution.md` with the template below. Ensure the `.specify/memory/` directory exists first:

```bash
mkdir -p .specify/memory
```

### 4. Create Constitution Content

**Template:**

```markdown
# Project Constitution

**Project:** [Project Name]
**Created:** YYYY-MM-DD
**Last Updated:** YYYY-MM-DD

## Purpose

This constitution defines project-wide principles, patterns, and standards.
All features and implementations must align with these principles.

## Architectural Principles

### [Principle Name]
**Description:** [What this principle means]
**Rationale:** [Why we follow this]
**Examples:**
- ✓ [Good example]
- ✗ [Bad example]

[Repeat for each principle]

## API Design Standards

### RESTful Conventions
- Use standard HTTP methods (GET, POST, PUT, DELETE)
- Plural resource names (/users, not /user)
- Return appropriate status codes
- Use JSON for request/response bodies

### Error Responses
**Format:**
```json
{
  "error": "Human-readable error message",
  "code": "ERROR_CODE",
  "details": { ... }
}
```

**Status Codes:**
- 400: Bad Request (client error)
- 401: Unauthorized (auth required)
- 403: Forbidden (auth insufficient)
- 404: Not Found
- 422: Unprocessable Entity (validation failed)
- 500: Internal Server Error

## Error Handling

### Approach
- All errors must be handled explicitly
- Use try-catch for I/O operations
- Log errors with context
- Return user-friendly messages

### Retry Logic
- Database operations: 3 retries with exponential backoff
- External APIs: 2 retries with fixed delay
- Timeout: 30 seconds for external calls

## Security Requirements

### Authentication
- All API endpoints require JWT authentication (except public endpoints)
- JWTs expire after 30 minutes
- Refresh tokens expire after 7 days

### Input Validation
- Validate all user input
- Sanitize before database operations
- Reject unexpected fields

### Secrets Management
- Never commit secrets to git
- Use environment variables
- Rotate secrets quarterly

## Testing Standards

### Coverage Requirements
- Minimum 80% code coverage
- 100% coverage for critical paths

### Test Types
- Unit tests for all functions
- Integration tests for API endpoints
- E2E tests for critical user flows

### Test Organization
- Tests in `tests/` directory
- Mirror source structure
- Use descriptive test names

## Performance Requirements

### Response Times
- API responses: < 200ms (p95)
- Database queries: < 50ms (p95)
- Page loads: < 2 seconds

### Scalability
- Design for 10,000 concurrent users
- Horizontal scaling preferred
- Stateless where possible

## Code Quality Standards

### Code Style
- Follow [ESLint/Prettier/etc.] configuration
- Consistent naming conventions
- Comments for complex logic only

### Code Review
- All code must be reviewed
- Spec compliance verified
- Tests required before merge

## Accessibility Standards

### WCAG Compliance
- Meet WCAG 2.1 Level AA
- Keyboard navigation required
- Screen reader compatible

## Documentation Standards

### Code Documentation
- JSDoc for public functions
- README in each module
- Architecture diagrams for complex systems

### Spec Documentation
- All features must have specs
- Specs updated with changes
- Specs validated before implementation

## Change Management

### Updating This Constitution
- Requires team discussion (if team)
- Document rationale for changes
- Update all affected specs
- Communicate changes

### Exceptions
- Exceptions must be documented in spec
- Requires justification
- Reviewed during code review

## Glossary

**[Term 1]:** [Definition]
**[Term 2]:** [Definition]

## Decision Log

### [Decision Date]: [Decision Title]
**Context:** [Why decision needed]
**Decision:** [What was decided]
**Rationale:** [Why this decision]
**Implications:** [What this affects]

[Add new decisions here]
```

### 5. Review and Refine

**Questions to ask:**
- Is this too restrictive?
- Is this clear enough?
- Can we realistically follow this?
- Does this reflect our actual practices?

**Adjust as needed.**

### 6. Validate Against Existing Specs

**Check existing specs:**
```bash
# For each existing spec
cat specs/features/[feature].md

# Does it align with constitution?
# Any violations?
```

**If violations found:**
- Update spec, OR
- Update constitution (if spec is right), OR
- Note as exception

### 7. Commit Constitution

```bash
git add .specify/memory/constitution.md
git commit -m "Add project constitution

Defines project-wide principles and standards:
- Architectural principles
- API design standards
- Error handling patterns
- Security requirements
- Testing standards
- Code quality standards

All future specs will be validated against this constitution.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### 8. Communicate and Adopt

**For team projects:**
- Share with team
- Get consensus
- Document exceptions
- Reference in onboarding

**For solo projects:**
- Keep visible
- Reference when creating specs
- Update as you learn

## Constitution Checklist

Use TodoWrite to track:

- [ ] Decide if constitution needed
- [ ] Gather existing patterns from specs/code
- [ ] Create constitution file (spec-kit or manual)
- [ ] Fill in all relevant sections
- [ ] Review for clarity and feasibility
- [ ] Validate against existing specs
- [ ] Handle any violations found
- [ ] Commit constitution to git
- [ ] Communicate to team (if applicable)

## Example Constitution

```markdown
# Todo App Project Constitution

**Created:** 2025-11-10

## Purpose

Define standards for the todo app project to ensure consistency.

## Architectural Principles

### RESTful API Design
All endpoints follow REST conventions:
- `GET /api/todos` - List todos
- `POST /api/todos` - Create todo
- `PUT /api/todos/:id` - Update todo
- `DELETE /api/todos/:id` - Delete todo

### Data Validation
- Validate on server (never trust client)
- Return 422 for validation failures
- Provide specific error messages

## Error Handling

### Error Response Format
```json
{
  "error": "Human-readable message",
  "field": "field_name",  // for validation errors
  "code": "ERROR_CODE"
}
```

### Common Errors
- 400: Malformed request
- 401: Not authenticated
- 404: Todo not found
- 422: Validation failed (e.g., title too long)

## Testing Standards

### Requirements
- All endpoints have integration tests
- All validation rules have tests
- Edge cases tested

### Coverage
- Minimum 80% coverage
- 100% coverage for API endpoints

## Code Quality

### Naming
- camelCase for variables and functions
- PascalCase for classes
- UPPER_CASE for constants

### Comments
- JSDoc for public functions
- Inline comments for complex logic only

## Security

### Authentication
- JWT tokens required for all /api/* endpoints
- Tokens expire after 1 hour
- Refresh on activity

### Input Sanitization
- Escape HTML in todo titles/descriptions
- Limit field lengths (title: 200 chars, description: 2000 chars)

## Decision Log

### 2025-11-10: Use JWT for Auth
**Context:** Need authentication for multi-user support
**Decision:** Use JWT tokens stored in httpOnly cookies
**Rationale:** Secure, stateless, industry standard
**Implications:** Need token refresh mechanism, logout handling
```

## Maintaining the Constitution

**Update when:**
- New patterns emerge
- Decisions change
- Standards evolve
- Exceptions become rules

**Don't update when:**
- Single feature needs exception
- Trying to justify shortcut
- Reacting to single issue

**Update process:**
1. Propose change
2. Update constitution
3. Update affected specs
4. Communicate change
5. Add to decision log

## Common Sections

### Minimal Constitution
- Architectural principles
- Error handling
- Testing standards

### Standard Constitution
- Above, plus:
- API design
- Security requirements
- Code quality

### Comprehensive Constitution
- Above, plus:
- Performance requirements
- Accessibility standards
- Deployment practices
- Monitoring/observability

**Start minimal, expand as needed.**

## Anti-Patterns

**Avoid:**
- Creating constitution too early (no patterns yet)
- Making it too restrictive (can't follow it)
- Copying from other projects (doesn't fit yours)
- Never updating it (becomes outdated)
- Not following it (then why have it?)

**Instead:**
- Wait for patterns to emerge
- Make it realistic and followable
- Extract from your own project
- Update as project evolves
- Enforce during spec validation

## Remember

**Constitution is living document.**

- Starts small, grows with project
- Reflects actual practices
- Updated as standards evolve
- Referenced regularly

**Constitution enables consistency.**

- Specs validated against it
- Reduces decision fatigue
- Onboards new developers
- Documents architectural decisions

**Constitution serves the project.**

- Not rigid rules set in stone
- Pragmatic guidelines
- Updated when they don't serve
- Exceptions documented

**Good constitution helps. Bad constitution hinders.**

Make yours helpful.
