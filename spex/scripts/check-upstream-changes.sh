#!/bin/bash
# Helper script: Check for upstream superpowers changes since last sync
# Usage: From project root: make check-upstream
#        Or from sdd/: ./scripts/check-upstream-changes.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check we're in the right directory
if [ ! -f ".superpowers-sync" ]; then
  echo -e "${RED}ERROR: .superpowers-sync not found${NC}"
  echo "This script must be run from the sdd/ directory"
  echo "Use 'make check-upstream' from the project root"
  exit 1
fi

echo -e "${GREEN}Checking for upstream superpowers changes...${NC}\n"

# Load sync state
LAST_SYNC=$(jq -r '.last_sync_commit' .superpowers-sync)
LAST_DATE=$(jq -r '.last_sync_date' .superpowers-sync)

echo "Last sync: $LAST_SYNC ($LAST_DATE)"
echo ""

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Clone upstream
echo "Cloning upstream superpowers..."
git clone --quiet https://github.com/obra/superpowers "$TEMP_DIR/superpowers" 2>&1 | grep -v "Cloning into" || true
cd "$TEMP_DIR/superpowers"

# Get current state
CURRENT_COMMIT=$(git rev-parse HEAD)
CURRENT_DATE=$(git log -1 --format=%cd --date=short)

echo -e "${GREEN}Upstream HEAD: $CURRENT_COMMIT ($CURRENT_DATE)${NC}"
echo ""

# Check if sync needed
if [ "$LAST_SYNC" = "INITIAL" ]; then
  echo -e "${YELLOW}⚠️  Initial sync needed${NC}"
  echo "Use /update-superpowers to establish baseline"
  exit 0
fi

if [ "$LAST_SYNC" = "$CURRENT_COMMIT" ]; then
  echo -e "${GREEN}✅ Already up to date!${NC}"
  exit 0
fi

# Show commits since last sync
echo -e "${YELLOW}Changes since last sync:${NC}\n"
git log --oneline --graph $LAST_SYNC..HEAD

echo ""
echo -e "${YELLOW}Modified skills to check:${NC}\n"

# Check each modified skill
SKILLS=("writing-plans" "code-review" "verification-before-completion" "brainstorming")
CHANGED=0

for skill in "${SKILLS[@]}"; do
  SKILL_FILE="skills/${skill}/SKILL.md"

  if git diff --quiet $LAST_SYNC..HEAD -- "$SKILL_FILE"; then
    echo -e "  ${GREEN}✓${NC} $skill - no changes"
  else
    echo -e "  ${YELLOW}●${NC} $skill - HAS CHANGES"
    CHANGED=$((CHANGED + 1))

    # Show commit count
    COUNT=$(git log --oneline $LAST_SYNC..HEAD -- "$SKILL_FILE" | wc -l | tr -d ' ')
    echo "    Commits: $COUNT"

    # Show commit messages
    git log --format="      - %s (%h)" $LAST_SYNC..HEAD -- "$SKILL_FILE"
    echo ""
  fi
done

echo ""
if [ $CHANGED -gt 0 ]; then
  echo -e "${YELLOW}⚡ $CHANGED skill(s) have upstream changes${NC}"
  echo ""
  echo "To sync, run: /update-superpowers"
  echo ""
  echo "Or to review changes manually:"
  echo "  cd $TEMP_DIR/superpowers"
  echo "  git diff $LAST_SYNC..HEAD -- skills/writing-plans/SKILL.md"
  echo ""
  echo "Temp directory: $TEMP_DIR"
  echo "(will be cleaned up on script exit)"
else
  echo -e "${GREEN}✅ No changes in modified skills${NC}"
fi
