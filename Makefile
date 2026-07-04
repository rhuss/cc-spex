.PHONY: validate install uninstall reinstall check-upstream test-hook test-install test-install-remote release migrate help

MARKETPLACE := spex-plugin-development
PLUGIN := spex@$(MARKETPLACE)

# Legacy names (pre-3.0.0)
OLD_MARKETPLACE := sdd-plugin-development
OLD_PLUGIN := sdd@$(OLD_MARKETPLACE)

validate:
	claude plugin validate ./
	claude plugin validate ./spex/

migrate:
	@# Remove old sdd plugin and marketplace from pre-3.0.0 installations
	@if claude plugin list 2>/dev/null | grep -q "$(OLD_PLUGIN)"; then \
		echo "Removing old sdd plugin..."; \
		claude plugin rm $(OLD_PLUGIN) 2>/dev/null || true; \
	fi
	@if claude plugin marketplace list 2>/dev/null | grep -q "$(OLD_MARKETPLACE)"; then \
		echo "Removing old sdd marketplace..."; \
		claude plugin marketplace rm $(OLD_MARKETPLACE) 2>/dev/null || true; \
	fi

install: migrate
	@# Add or update marketplace
	@if claude plugin marketplace add ./ 2>&1 | grep -q "already installed"; then \
		echo "Updating marketplace..."; \
		claude plugin marketplace update $(MARKETPLACE); \
	else \
		echo "Marketplace added."; \
	fi
	@# Install or reinstall plugin
	@if claude plugin list 2>/dev/null | grep -q "$(PLUGIN)"; then \
		echo "Plugin already installed, reinstalling..."; \
		claude plugin rm $(PLUGIN) 2>/dev/null || true; \
	fi
	claude plugin install $(PLUGIN)

uninstall:
	@echo "Removing plugin..."
	@claude plugin rm $(PLUGIN) 2>/dev/null || echo "Plugin not installed"
	@echo "Removing marketplace..."
	@claude plugin marketplace rm $(MARKETPLACE) 2>/dev/null || echo "Marketplace not installed"

reinstall: uninstall install

test-hook:
	@echo "Testing context-hook.py..."
	@echo '{"prompt":"/spex:init","session_id":"test","cwd":"/tmp","hook_event_name":"UserPromptSubmit"}' | \
		python3 spex/scripts/hooks/context-hook.py

test-install:
	@./tests/test_marketplace_install.sh --local

test-install-remote:
	@./tests/test_marketplace_install.sh

release: validate test-install
	@VERSION=$$(cat VERSION 2>/dev/null | tr -d '[:space:]'); \
	if [ -z "$$VERSION" ]; then \
		echo "Error: VERSION file not found or empty"; exit 1; \
	fi; \
	case "$$VERSION" in \
		*-dev*) echo "Error: Cannot release a dev version ($$VERSION). Remove -dev suffix from VERSION first."; exit 1;; \
	esac; \
	if git tag -l "v$$VERSION" | grep -q .; then \
		echo "Error: Tag v$$VERSION already exists"; exit 1; \
	fi; \
	echo "Releasing v$$VERSION..."; \
	echo ""; \
	echo "Updating marketplace.json version to $$VERSION..."; \
	tmp=$$(mktemp); \
	jq --arg v "$$VERSION" '(.plugins[] | select(.name == "spex")).version = $$v' .claude-plugin/marketplace.json > "$$tmp" && mv "$$tmp" .claude-plugin/marketplace.json; \
	git add VERSION .claude-plugin/marketplace.json; \
	git commit -m "chore: bump version to $$VERSION"; \
	echo "Creating tag v$$VERSION..."; \
	git tag "v$$VERSION"; \
	echo "Pushing release commit and tag..."; \
	git push && git push origin "v$$VERSION"; \
	echo "Creating GitHub release..."; \
	gh release create "v$$VERSION" --generate-notes; \
	echo ""; \
	PATCH=$$(echo "$$VERSION" | cut -d. -f3); \
	NEXT_PATCH=$$((PATCH + 1)); \
	NEXT_VERSION=$$(echo "$$VERSION" | cut -d. -f1,2).$$NEXT_PATCH-dev; \
	echo "Bumping VERSION to $$NEXT_VERSION..."; \
	echo "$$NEXT_VERSION" > VERSION; \
	git add VERSION; \
	git commit -m "chore: bump version to $$NEXT_VERSION"; \
	git push; \
	echo ""; \
	echo "Release v$$VERSION complete. VERSION bumped to $$NEXT_VERSION."

check-upstream:
	cd spex && ./scripts/check-upstream-changes.sh

help:
	@echo "Available targets:"
	@echo "  validate       - Validate plugin manifests"
	@echo "  install        - Install plugin (adds marketplace, installs/updates plugin)"
	@echo "  uninstall      - Remove plugin and marketplace"
	@echo "  reinstall      - Full uninstall and reinstall"
	@echo "  migrate        - Remove old sdd plugin/marketplace (run automatically by install)"
	@echo "  test-hook      - Test the context hook"
	@echo "  test-install   - Integration test: install from local marketplace"
	@echo "  test-install-remote - Integration test: install from GitHub marketplace"
	@echo "  release        - Full release: validate, update marketplace.json, tag, push, bump to dev"
	@echo "  check-upstream - Check for upstream superpowers changes"
