# Quickstart: spex:ship

## Prerequisites

1. spex plugin installed (`make install`)
2. Traits enabled: `superpowers` and `deep-review`
   ```
   /spex:traits enable superpowers deep-review
   ```
3. A brainstorm document in `brainstorm/`

## Basic Usage

```
/spex:ship brainstorm/05-my-feature.md
```

This runs the full pipeline: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, verify.

## Auto-detect Brainstorm

```
/spex:ship
```

Automatically picks the highest-numbered brainstorm file.

## Ask Levels

```
# Stop at every review finding (learning/critical features)
/spex:ship --ask always

# Auto-fix clear issues, pause on ambiguous ones (default)
/spex:ship --ask balanced

# Fix everything, only stop on blockers
/spex:ship --ask never
```

## With PR Creation

```
/spex:ship --create-pr --ask never
```

## Skip External Reviews

```
/spex:ship --no-external
```

## Development Workflow

1. Create a new SKILL.md at `spex/skills/ship/SKILL.md`
2. Register the skill in the plugin's skill manifest
3. Implement argument parsing following the `review-code` pattern
4. Implement pipeline orchestration with state tracking
5. Test with a brainstorm document in each ask mode
