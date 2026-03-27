---
name: spec-refactoring
description: Consolidate and improve evolved specs - identifies inconsistencies, removes redundancy, improves structure while maintaining feature coverage
---

# Specification Refactoring

## Overview

Refactor specifications that have grown organically to improve clarity, consistency, and maintainability.

As specs evolve through `sdd:evolve`, they can accumulate:
- Inconsistencies
- Redundancies
- Unclear sections
- Poor organization

This skill consolidates and improves specs while ensuring all implemented features remain covered.

## When to Use

- Spec has evolved significantly through multiple updates
- Multiple related specs have redundancy
- Spec is difficult to understand or implement from
- Before major feature work on legacy spec
- Periodic maintenance (quarterly review)

**Warning:** Never refactor specs during active implementation. Wait until stable.

## The Process

### 1. Analyze Current State

**Read all related specs:**
```bash
# Single spec
cat specs/features/[feature].md

# Multiple related specs
cat specs/features/user-*.md
```

**Document current issues:**
- Inconsistencies (conflicting requirements)
- Redundancies (duplicate requirements)
- Unclear sections (ambiguities)
- Poor structure (hard to navigate)
- Outdated sections (no longer relevant)

### 2. Review Implementation

**Check what's actually implemented:**
```bash
# Find implementation
rg "[feature-related-terms]" src/

# Check tests
rg "[feature-related-terms]" tests/
```

**Critical:** Refactored spec MUST cover all implemented features.

**Create coverage map:**
```
Implemented Feature 1 → Spec Requirement X
Implemented Feature 2 → Spec Requirement Y
...
```

If implementation exists without spec coverage, ADD it during refactor.

### 3. Identify Consolidation Opportunities

**Look for:**

**Redundant requirements:**
- Same requirement stated multiple times
- Similar requirements that could merge
- Duplicate error handling

**Inconsistent terminology:**
- Same concept called different names
- Inconsistent capitalization
- Different formats for similar things

**Scattered related requirements:**
- Auth requirements in multiple places
- Error handling spread throughout
- Related features not grouped

### 4. Design Improved Structure

**Better organization:**
- Group related requirements
- Logical section order
- Consistent formatting
- Clear hierarchy

**Example improvement:**

**Before:**
```markdown
## Requirements
- User login
- Password validation
- Email validation
- Session management
- Logout
- Password reset
- Email verification
```

**After:**
```markdown
## Authentication Requirements

### User Registration
- Email validation
- Email verification
- Password validation

### Session Management
- User login
- Session creation
- Logout
- Session expiration

### Password Management
- Password reset
- Password change
- Password strength requirements
```

### 5. Refactor Spec

**Steps:**

1. **Create refactored version** (new file or branch)
2. **Reorganize sections** for clarity
3. **Consolidate redundancies**
4. **Standardize terminology**
5. **Improve requirement clarity**
6. **Add missing coverage** (if implementation exists)
7. **Remove obsolete sections** (if truly no longer relevant)

**Throughout:** Maintain traceability to old spec

### 6. Validate Refactored Spec

**Check:**
- [ ] All implemented features covered
- [ ] No requirements lost
- [ ] Terminology consistent
- [ ] Structure logical
- [ ] No new ambiguities introduced

**Use `sdd:review-spec`** on refactored version.

### 7. Create Changelog

**Document changes:**

```markdown
## Spec Refactoring Changelog

**Date:** YYYY-MM-DD
**Previous Version:** [link or commit]

### Changes Made

**Structural Changes:**
- Reorganized requirements into logical groups
- Moved error handling to dedicated section
- Created sub-sections for clarity

**Consolidated Requirements:**
- Merged requirements 3, 7, 12 (all about validation)
- Combined duplicate error cases
- Unified session management requirements

**Terminology Standardization:**
- "User" → "Authenticated User" (consistent usage)
- "Login" → "Authentication" (aligned with codebase)

**Added Coverage:**
- Requirement 15: Password strength (implemented but not in spec)
- Error case 8: Rate limiting (implemented but not in spec)

**Removed:**
- Obsolete requirement 9 (feature removed in v2.0)

### Migration Notes

[How to map old spec sections to new spec sections]

Old Section 2.1 → New Section 3.1.1
Old Section 3.4 → New Section 2.3
...
```

### 8. Transition Strategy

**For active projects:**

1. **Review with team** (if team project)
2. **Create PR for spec refactor**
3. **Get approval before merging**
4. **Keep old spec accessible** (git history)
5. **Update documentation** (if references spec)

**For solo projects:**

1. **Commit old spec** (ensure it's in git)
2. **Replace with refactored spec**
3. **Commit with detailed message**

### 9. Verify Against Code

**After refactoring:**

```bash
# Check spec compliance with current code
# Use sdd:review-code
```

**Ensure:**
- Refactored spec still describes existing implementation
- No accidental requirement changes
- Compliance still 100%

## Refactoring Checklist

Use TodoWrite to track:

- [ ] Analyze current spec state (issues, redundancies)
- [ ] Review actual implementation (what exists in code)
- [ ] Create coverage map (implementation → spec)
- [ ] Identify consolidation opportunities
- [ ] Design improved structure
- [ ] Refactor spec content
- [ ] Validate refactored spec for soundness
- [ ] Ensure all implemented features covered
- [ ] Create changelog documenting changes
- [ ] Verify refactored spec against code (compliance check)
- [ ] Commit with detailed message

## Example: Before and After

### Before Refactoring

```markdown
# Feature: User System

## Requirements
1. Users can register
2. Email must be validated
3. Password must be strong
4. Users can login
5. Sessions expire after 30 minutes
6. Users can logout
7. Passwords must have 8 characters
8. Passwords must have uppercase
9. Passwords must have lowercase
10. Passwords must have number
11. Email format must be valid
12. Users can reset password
13. Reset tokens expire after 1 hour
14. Users get logged out on password change
15. Sessions use JWT
16. JWT secret must be secure
...

(Requirements scattered, no organization, redundancy)
```

### After Refactoring

```markdown
# Feature: User Authentication System

## Purpose
Provide secure user authentication with registration, login, and password management.

## User Registration

### Functional Requirements
1. Users can register with email and password
2. Registration creates user account and initial session

### Email Validation
- Must be valid email format (RFC 5322)
- Email verification required before account activation
- Verification link expires after 24 hours

### Password Requirements
- Minimum 8 characters
- Must contain: uppercase, lowercase, number
- Common passwords rejected (check against list)

## Session Management

### Authentication Flow
1. User provides credentials (email + password)
2. System validates credentials
3. On success: JWT token generated
4. Client stores token for subsequent requests

### Session Configuration
- Token type: JWT (JSON Web Token)
- Token expiration: 30 minutes
- Secret: Stored in environment variable (not in code)
- Algorithm: HS256

### Logout
- Client discards token
- Optional: Server-side token invalidation (if implemented)

## Password Management

### Password Reset
- User requests reset via email
- Reset token generated and emailed
- Reset token expires after 1 hour
- On successful reset: all sessions invalidated

### Password Change
- Requires current password confirmation
- On success: all sessions invalidated (forces re-login)
...

(Organized, consolidated, clear)
```

### Changelog for Above

```markdown
## Spec Refactoring Changelog

**Date:** 2025-11-10

### Structural Changes
- Reorganized flat list into hierarchical sections:
  - User Registration
  - Session Management
  - Password Management

### Consolidated Requirements
- Requirements 7-10 → Single "Password Requirements" section
- Requirements 2, 11 → "Email Validation" section
- Requirements 4, 5, 6, 15, 16 → "Session Management" section

### Terminology Standardization
- Consistently use "JWT" (not "token" and "JWT" interchangeably)
- "User" context now explicit (authenticated vs unauthenticated)

### Added Coverage
- None (all features already in original spec)

### Removed
- None (all requirements preserved, just reorganized)
```

## Types of Refactoring

### 1. Structural Refactoring
- Reorganize sections
- Create hierarchy
- Group related items
- Improve navigation

### 2. Consolidation Refactoring
- Merge duplicate requirements
- Combine scattered related items
- Remove redundancy

### 3. Clarification Refactoring
- Remove ambiguities
- Add specificity
- Improve wording
- Standardize terminology

### 4. Coverage Refactoring
- Add missing implemented features
- Remove obsolete requirements
- Align with current codebase

## Common Patterns

### Pattern: Password Requirements Scattered

**Problem:** Password requirements in multiple places

**Solution:** Consolidate into single "Password Requirements" section

### Pattern: Inconsistent Error Handling

**Problem:** Some requirements specify errors, others don't

**Solution:** Create dedicated "Error Handling" section, reference from requirements

### Pattern: Mixed Abstraction Levels

**Problem:** High-level and low-level requirements mixed

**Solution:** Create hierarchy - high-level functional requirements with detailed sub-sections

### Pattern: Terminology Drift

**Problem:** "User", "Account", "Profile" used interchangeably

**Solution:** Standardize on one term, define others in glossary if needed

## Warnings

**Don't:**
- Change requirements (that's spec evolution, not refactoring)
- Remove coverage of implemented features
- Refactor during active implementation
- Make untracked changes (always document)

**Do:**
- Preserve all requirement content
- Improve organization and clarity
- Maintain traceability
- Document all changes

## Remember

**Refactoring improves form, not function.**

- Same requirements, better organization
- Same coverage, better clarity
- Same intent, better structure

**Refactoring is maintenance, not change.**

- Spec still describes same implementation
- No behavioral changes
- Only organizational improvements

**Good specs enable good work.**

- Clear specs enable smooth implementation
- Organized specs reduce confusion
- Consistent specs prevent errors

**Periodic refactoring prevents spec decay.**
