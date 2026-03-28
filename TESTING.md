# Testing Guide for cc-spex

This document provides a comprehensive testing plan to validate that the cc-spex plugin works as intended.

## Prerequisites

- [ ] Claude Code installed and working
- [ ] Plugin symlinked to `~/.claude/plugins/cc-spex`
- [ ] Fresh Claude Code instance started
- [ ] Test project available (existing or new)

## Test Environment Setup

### Verify Plugin Installation

**Step 1: Check plugin directory**
```bash
ls -la ~/.claude/plugins/cc-spex
```

**Expected:** Symlink pointing to development directory

**Step 2: Verify plugin structure**
```bash
ls ~/.claude/plugins/cc-spex/
```

**Expected output:**
```
LICENSE
Makefile
README.md
docs/
examples/
spex/
```

**Step 3: Check plugin.json is valid**
```bash
cat ~/.claude/plugins/cc-spex/spex/.claude-plugin/plugin.json | python3 -m json.tool
```

**Expected:** Valid JSON output with no errors

### Start Fresh Claude Code Instance

**Step 4: Restart Claude Code**
- Quit Claude Code completely
- Start new instance in test project directory

**Step 5: Verify plugin loaded**

In Claude Code, ask:
```
What spex skills are available?
```

**Expected:** List of all 12 skills:
- spex:using-superpowers
- spex:brainstorm
- spex:spec
- spex:implement
- spex:evolve
- spex:writing-plans
- spex:review-code
- spex:verification-before-completion
- spex:review-spec
- spex:spec-refactoring
- spex:spec-kit

---

## Phase 1: Entry Skill & Skill Discovery

### Test 1.1: Entry Skill Invocation

**Objective:** Verify the entry skill loads and establishes workflows

**Steps:**
1. In Claude Code, type: `What is specification-driven development?`
2. Observe if Claude mentions using spex skills

**Expected:**
- [ ] Entry skill concepts mentioned
- [ ] Workflow overview provided
- [ ] Skill recommendations given

**Pass Criteria:** Claude demonstrates awareness of spex workflow

---

### Test 1.2: Skill Tool Discovery

**Objective:** Verify skills are discoverable and invokable

**Steps:**
1. Ask: `Show me how to use /spex:brainstorm`

**Expected:**
- [ ] Skill purpose explained
- [ ] When to use it described
- [ ] Example workflow shown

**Pass Criteria:** Skill information is clear and actionable

---

## Phase 2: Constitution Workflow

### Test 2.1: Constitution Creation

**Objective:** Create a project constitution from scratch

**Steps:**
1. Invoke: `/speckit.constitution` or ask: "Create a constitution for this project"
2. Follow the interactive prompts
3. Verify constitution created at `.specify/memory/constitution.md`

**Expected:**
- [ ] Constitution file created
- [ ] Contains sections: Purpose, Architectural Principles, Standards
- [ ] File is valid markdown
- [ ] Committed to git (if requested)

**Pass Criteria:** Constitution created with sensible defaults and clear structure

**Test Data:**
```
Project type: Web API
Patterns: RESTful, JSON responses
Standards: ESLint, Prettier
```

---

### Test 2.2: Constitution Validation

**Objective:** Verify created constitution is well-formed

**Steps:**
1. Read `.specify/memory/constitution.md`
2. Check for required sections
3. Verify no placeholder text (TBD, TODO, etc.)

**Expected:**
- [ ] All sections present and filled
- [ ] Examples provided for key patterns
- [ ] Decision log initialized
- [ ] Realistic and followable standards

**Pass Criteria:** Constitution is complete and usable

---

## Phase 3: Spec Creation Workflows

### Test 3.1: Brainstorming to Spec

**Objective:** Create spec from rough idea using brainstorming

**Steps:**
1. Invoke: `/spex:brainstorm`
2. Provide rough idea: "I want to add user authentication to the app"
3. Answer questions as they're asked
4. Verify spec created

**Expected:**
- [ ] Claude asks clarifying questions (one at a time)
- [ ] Multiple approaches offered with trade-offs
- [ ] Spec created at `specs/features/[feature-name].md`
- [ ] Spec validated against constitution (if exists)
- [ ] Offers next steps (review or implement)

**Pass Criteria:**
- Questions are helpful and lead to clarity
- Spec is comprehensive and implementable
- Process feels collaborative, not interrogative

**Notes:**
Record any unclear questions or workflow issues.

---

### Test 3.2: Direct Spec Creation

**Objective:** Create spec directly from clear requirements

**Steps:**
1. Invoke: `/spex:spec`
2. Provide clear requirements:
   ```
   Create a spec for a REST API endpoint:
   - GET /api/users/:id
   - Returns user object with id, name, email
   - Returns 404 if user not found
   - Requires authentication
   ```
3. Verify spec created

**Expected:**
- [ ] Spec created quickly (no extensive Q&A)
- [ ] All provided requirements captured
- [ ] Error cases included
- [ ] Success criteria defined
- [ ] Validates against constitution

**Pass Criteria:** Spec accurately reflects requirements without unnecessary questions

---

### Test 3.3: Spec Review for Soundness

**Objective:** Review created spec for completeness and clarity

**Steps:**
1. Create a spec (via brainstorm or direct)
2. Invoke: `/spex:review-spec` or ask: "Review the spec for soundness"
3. Review the feedback

**Expected:**
- [ ] Completeness checked (all sections present)
- [ ] Clarity checked (no ambiguous language)
- [ ] Implementability assessed
- [ ] Testability verified
- [ ] Constitution alignment checked (if constitution exists)
- [ ] Issues identified with specific recommendations

**Pass Criteria:**
- Sound specs pass review
- Problematic specs get actionable feedback

**Test Cases:**

**a) Good spec:** Should pass review
**b) Ambiguous spec:** Create spec with vague terms like "fast", "user-friendly" - should be flagged
**c) Incomplete spec:** Create spec missing error handling - should be flagged

---

## Phase 4: Implementation Workflow

### Test 4.1: Plan Generation from Spec

**Objective:** Generate implementation plan from validated spec

**Steps:**
1. Ensure spec exists and is validated
2. Invoke: `/spex:implement` or ask: "Create implementation plan from spec"
3. Observe plan generation

**Expected:**
- [ ] Plan generated at `docs/plans/[date]-[feature]-implementation.md`
- [ ] All spec requirements covered
- [ ] Tasks include specific file paths
- [ ] Test strategy defined
- [ ] Error cases addressed
- [ ] 100% requirement coverage validated

**Pass Criteria:** Plan is detailed enough to implement from without referring back to spec constantly

---

### Test 4.2: Plan Validation Against Spec

**Objective:** Ensure plan covers all spec requirements

**Steps:**
1. Review generated plan
2. Compare to original spec
3. Check coverage matrix

**Expected:**
- [ ] Each functional requirement → tasks mapping
- [ ] Each error case → implementation approach
- [ ] Each edge case → test case
- [ ] No requirements missing
- [ ] No extra features beyond spec

**Pass Criteria:** 100% spec coverage in plan

---

### Test 4.3: Implementation Workflow (Conceptual)

**Objective:** Test implementation workflow awareness

**Note:** Full implementation not required, test workflow understanding

**Steps:**
1. Ask: "What's the process for implementing this feature?"
2. Verify workflow described

**Expected:**
- [ ] Mentions TDD (test-first)
- [ ] References spec compliance checking
- [ ] Describes verification gates
- [ ] Explains code review process

**Pass Criteria:** Workflow matches spex principles

---

## Phase 5: Spec Evolution

### Test 5.1: Detect Spec/Code Mismatch

**Objective:** Simulate spec/code divergence and test detection

**Steps:**
1. Create a spec with specific requirement (e.g., "Return 422 for validation errors")
2. Describe implementation that differs (e.g., "Code returns 400 instead of 422")
3. Invoke: `/spex:evolve` or ask: "There's a mismatch between spec and code"

**Expected:**
- [ ] Mismatch detected and described
- [ ] Type categorized (behavioral, cosmetic, etc.)
- [ ] Severity assessed (minor, major, critical)
- [ ] Impact analyzed

**Pass Criteria:** Mismatch clearly identified and categorized

---

### Test 5.2: AI Recommendation for Resolution

**Objective:** Test AI's ability to recommend spec vs code fix

**Steps:**
1. Continue from Test 5.1
2. Review AI recommendation

**Expected:**
- [ ] Clear recommendation (update spec OR fix code OR clarify spec)
- [ ] Reasoning provided
- [ ] Trade-offs explained
- [ ] User impact considered

**Pass Criteria:** Recommendation is sensible with clear reasoning

**Test Cases:**

**a) Minor addition:** Code adds helpful field not in spec
- Expected: Recommend update spec

**b) Missing feature:** Spec requires feature, code doesn't have it
- Expected: Recommend fix code

**c) Ambiguous spec:** Spec unclear, code made reasonable choice
- Expected: Recommend clarify spec

---

### Test 5.3: Auto-Update Configuration

**Objective:** Test auto-update threshold configuration

**Steps:**
1. Create `.claude/settings.json` with:
   ```json
   {
     "spex": {
       "auto_update_spec": {
         "enabled": true,
         "threshold": "minor",
         "notify": true
       }
     }
   }
   ```
2. Present minor mismatch
3. Observe behavior

**Expected:**
- [ ] Minor mismatches auto-updated
- [ ] Notification provided
- [ ] Changelog updated
- [ ] Major mismatches still require user decision

**Pass Criteria:** Configuration respected, notifications clear

---

## Phase 6: Code Review & Verification

### Test 6.1: Code Review Against Spec

**Objective:** Test spec compliance checking

**Steps:**
1. Provide spec and implementation code
2. Invoke: `/spex:review-code`
3. Review compliance report

**Expected:**
- [ ] Compliance score calculated (%)
- [ ] Each requirement checked
- [ ] Deviations identified
- [ ] Extra features noted
- [ ] Recommendation provided

**Pass Criteria:** Accurate compliance assessment with clear reporting

**Test Cases:**

**a) 100% compliant:** Should report 100% with approval
**b) Missing requirement:** Should identify gap
**c) Extra feature:** Should note as deviation

---

### Test 6.2: Verification Before Completion

**Objective:** Test complete verification workflow

**Steps:**
1. Describe implementation state (tests + spec compliance)
2. Invoke: `/spex:verification-before-completion`
3. Review verification report

**Expected:**
- [ ] Tests status checked
- [ ] Spec compliance validated
- [ ] Spec drift checked
- [ ] Success criteria verified
- [ ] Go/no-go decision made
- [ ] Blocking issues identified if fails

**Pass Criteria:**
- Verified implementations pass
- Incomplete implementations blocked with clear reasons

---

## Phase 7: Spec Maintenance

### Test 7.1: Spec Refactoring

**Objective:** Test spec consolidation and improvement

**Steps:**
1. Create spec with some redundancy or inconsistency
2. Invoke: `/spex:spec-refactoring`
3. Review refactored spec

**Expected:**
- [ ] Redundancies identified and consolidated
- [ ] Inconsistencies fixed
- [ ] Structure improved
- [ ] All implemented features still covered
- [ ] Changelog documenting changes

**Pass Criteria:** Refactored spec is clearer while maintaining coverage

---

### Test 7.2: Constitution Updates

**Objective:** Test constitution evolution

**Steps:**
1. With existing constitution, propose update
2. Update constitution
3. Verify decision log updated

**Expected:**
- [ ] Constitution updated with changes
- [ ] Decision log entry created
- [ ] Rationale documented
- [ ] Affects existing specs noted

**Pass Criteria:** Constitution changes properly documented

---

## Phase 8: Spec-Kit Integration

### Test 8.1: Spec-Kit Available

**Objective:** Test integration when spec-kit is installed

**Prerequisites:** spec-kit installed (`which specify` succeeds)

**Steps:**
1. Create spec using `/spex:spec`
2. Observe if spec-kit is used

**Expected:**
- [ ] Spec-kit detected
- [ ] Spec-kit commands used
- [ ] spex validation added on top
- [ ] Graceful operation

**Pass Criteria:** Spec-kit integration seamless

---

### Test 8.2: Spec-Kit Not Available

**Objective:** Test graceful degradation without spec-kit

**Prerequisites:** spec-kit not installed

**Steps:**
1. Create spec using `/spex:spec`
2. Observe fallback behavior

**Expected:**
- [ ] Spec-kit absence noted (optional message)
- [ ] Manual spec creation works
- [ ] spex validation still works
- [ ] No errors or blocking issues

**Pass Criteria:** Plugin fully functional without spec-kit

---

## Phase 9: TodoWrite Integration

### Test 9.1: Checklist Tracking

**Objective:** Verify TodoWrite used for skill checklists

**Steps:**
1. Invoke skill with checklist (e.g., `/spex:implement`)
2. Observe TodoWrite usage

**Expected:**
- [ ] TodoWrite todos created for checklist items
- [ ] Tasks marked in_progress when working
- [ ] Tasks marked completed when done
- [ ] One task in_progress at a time

**Pass Criteria:** Checklist items properly tracked

---

### Test 9.2: Progress Visibility

**Objective:** Ensure user can see progress

**Steps:**
1. During multi-step workflow, check todo list status
2. Verify visibility of current task

**Expected:**
- [ ] Current task clearly shown
- [ ] Progress visible
- [ ] Completed tasks marked
- [ ] Pending tasks visible

**Pass Criteria:** User can track workflow progress

---

## Phase 10: End-to-End Workflow

### Test 10.1: Complete Feature Development

**Objective:** Full spex workflow from idea to verification

**Steps:**
1. Start with rough idea
2. `/spex:brainstorm` → create spec
3. `/spex:review-spec` → validate spec
4. `/spex:implement` → generate plan
5. Describe implementation
6. `/spex:review-code` → check compliance
7. `/spex:verification-before-completion` → verify complete

**Expected:**
- [ ] Smooth progression through all phases
- [ ] Each phase adds value
- [ ] No confusing transitions
- [ ] Clear next steps throughout
- [ ] Spec remains source of truth

**Pass Criteria:** Complete workflow feels natural and helpful

**Time Estimate:** 30-45 minutes

---

## Phase 11: Error Handling & Edge Cases

### Test 11.1: Missing Spec

**Objective:** Test behavior when spec doesn't exist

**Steps:**
1. Try to implement without spec
2. Observe error/guidance

**Expected:**
- [ ] Error or warning shown
- [ ] Guidance to create spec first
- [ ] Offers to create spec
- [ ] Doesn't proceed without spec

**Pass Criteria:** Enforces spec-first discipline

---

### Test 11.2: Invalid Spec Format

**Objective:** Test handling of malformed specs

**Steps:**
1. Create spec with invalid format
2. Try to use it

**Expected:**
- [ ] Invalid format detected
- [ ] Specific issues identified
- [ ] Recommendations for fixing
- [ ] Doesn't proceed with invalid spec

**Pass Criteria:** Invalid specs caught early

---

### Test 11.3: Spec-Code Major Divergence

**Objective:** Test handling of significant mismatches

**Steps:**
1. Present spec and code with major differences
2. Invoke `/spex:evolve`

**Expected:**
- [ ] Severity correctly identified as major
- [ ] Multiple mismatches all identified
- [ ] Prioritized recommendations
- [ ] User decision required (no auto-update)

**Pass Criteria:** Major issues handled seriously

---

## Phase 12: Performance & Usability

### Test 12.1: Skill Response Time

**Objective:** Ensure skills respond promptly

**Steps:**
1. Invoke various skills
2. Note response times

**Expected:**
- [ ] Initial response < 5 seconds
- [ ] Interactive responses feel natural
- [ ] No long pauses without explanation

**Pass Criteria:** Responsive interactions

---

### Test 12.2: Error Messages

**Objective:** Test error message clarity

**Steps:**
1. Trigger various error conditions
2. Review error messages

**Expected:**
- [ ] Errors clearly explained
- [ ] Actionable next steps provided
- [ ] No cryptic messages
- [ ] Helpful context included

**Pass Criteria:** Errors are helpful, not frustrating

---

### Test 12.3: Documentation Quality

**Objective:** Test inline skill documentation

**Steps:**
1. Read through skill instructions during use
2. Evaluate clarity

**Expected:**
- [ ] Instructions clear and concise
- [ ] Examples helpful
- [ ] No ambiguous language
- [ ] Checklists complete

**Pass Criteria:** Self-documenting workflow

---

## Test Results Template

Use this template to record test results:

```markdown
## Test Session: [Date]

**Tester:** [Name]
**Environment:**
- Claude Code Version:
- OS:
- Spec-kit installed: Yes/No

### Tests Executed

#### Phase 1: Entry Skill & Skill Discovery
- [ ] Test 1.1: Entry Skill Invocation - PASS/FAIL
  - Notes:
- [ ] Test 1.2: Skill Tool Discovery - PASS/FAIL
  - Notes:

[Continue for all tests...]

### Summary
- Total Tests:
- Passed:
- Failed:
- Blocked:

### Critical Issues Found
1. [Issue description]
2. [Issue description]

### Recommendations
1. [Improvement]
2. [Improvement]
```

---

## Success Criteria

### Minimum Viable (Must Pass)
- [ ] All Phase 1 tests (skill discovery)
- [ ] All Phase 3 tests (spec creation)
- [ ] Test 5.1, 5.2 (spec evolution)
- [ ] Test 6.1 (code review)
- [ ] Test 8.2 (works without spec-kit)
- [ ] Test 11.1 (enforces spec-first)

### Full Validation (Should Pass)
- [ ] All tests in Phases 1-9
- [ ] At least one complete end-to-end test
- [ ] All error handling tests

### Excellence (Nice to Have)
- [ ] All tests pass
- [ ] Performance tests meet criteria
- [ ] No usability issues
- [ ] Documentation clear throughout

---

## Issue Reporting

When you find issues during testing, document:

1. **Test ID:** (e.g., Test 3.1)
2. **Issue Description:** Clear description of what went wrong
3. **Expected Behavior:** What should have happened
4. **Actual Behavior:** What actually happened
5. **Severity:** Critical / Major / Minor / Trivial
6. **Steps to Reproduce:** Detailed steps
7. **Suggested Fix:** If you have ideas

---

## Next Steps After Testing

1. **Document Results:** Fill out test results template
2. **File Issues:** Create GitHub issues for failures
3. **Prioritize Fixes:** Critical → Major → Minor
4. **Iterate:** Fix and re-test
5. **Release:** When all critical tests pass

---

**Happy Testing! 🧪**
