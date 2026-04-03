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
	@VERSION=$$(jq -r '.plugins[] | select(.name == "spex") | .version' .claude-plugin/marketplace.json); \
	if git tag -l "v$$VERSION" | grep -q .; then \
		echo "Error: Tag v$$VERSION already exists"; exit 1; \
	fi; \
	echo ""; \
	echo "All checks passed. Ready to release v$$VERSION."; \
	echo "Run:  gh release create v$$VERSION --generate-notes"

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
	@echo "  release        - Pre-release checks (validate + test-install)"
	@echo "  check-upstream - Check for upstream superpowers changes"
