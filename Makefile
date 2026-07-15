.PHONY: validate install uninstall reinstall check-upstream test-hook test-install test-install-remote release migrate sync-scripts sync-scripts-check help

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

release: validate sync-scripts-check test-install
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
	echo "Updating version to $$VERSION in marketplace.json, plugin.json, setup.yml, bundle.yml, and spex/VERSION..."; \
	tmp=$$(mktemp); \
	jq --arg v "$$VERSION" '(.plugins[] | select(.name == "spex")).version = $$v' .claude-plugin/marketplace.json > "$$tmp" && mv "$$tmp" .claude-plugin/marketplace.json; \
	tmp=$$(mktemp); \
	jq --arg v "$$VERSION" '.version = $$v' spex/.claude-plugin/plugin.json > "$$tmp" && mv "$$tmp" spex/.claude-plugin/plugin.json; \
	sed -i.bak "s/^  version: \".*\"/  version: \"$$VERSION\"/" spex/setup.yml && rm -f spex/setup.yml.bak; \
	sed -i.bak "s/^  version: \".*\"/  version: \"$$VERSION\"/" spex/bundle.yml && rm -f spex/bundle.yml.bak; \
	echo "$$VERSION" > spex/VERSION; \
	git add VERSION spex/VERSION .claude-plugin/marketplace.json spex/.claude-plugin/plugin.json spex/setup.yml spex/bundle.yml; \
	git commit -m "chore: bump version to $$VERSION"; \
	echo "Creating tag v$$VERSION..."; \
	git tag "v$$VERSION"; \
	echo "Pushing release commit and tag..."; \
	git push && git push origin "v$$VERSION"; \
	echo "Creating GitHub release..."; \
	gh release create "v$$VERSION" spex/setup.yml --generate-notes; \
	echo ""; \
	PATCH=$$(echo "$$VERSION" | cut -d. -f3); \
	NEXT_PATCH=$$((PATCH + 1)); \
	NEXT_VERSION=$$(echo "$$VERSION" | cut -d. -f1,2).$$NEXT_PATCH-dev; \
	echo "Bumping VERSION to $$NEXT_VERSION..."; \
	echo "$$NEXT_VERSION" > VERSION; \
	echo "$$NEXT_VERSION" > spex/VERSION; \
	git add VERSION spex/VERSION; \
	git commit -m "chore: bump version to $$NEXT_VERSION"; \
	git push; \
	echo ""; \
	echo "Release v$$VERSION complete. VERSION bumped to $$NEXT_VERSION."

# Script inventory: which canonical scripts (in spex/scripts/) belong to which extensions
SCRIPTS_spex := spex-flow-state.sh spex-ship-state.sh spex-ship-state.py spex-ship-statusline.sh spex-finish-context.sh spex-worktree-cwd.sh
SCRIPTS_spex_gates := spex-flow-state.sh spex-closeout-gate.sh
SCRIPTS_spex_collab := spex-flow-state.sh spex-triage-state.sh sanitize-gh-json.py
SCRIPTS_spex_deep_review := spex-flow-state.sh
EXTENSIONS := spex spex-gates spex-collab spex-deep-review

sync-scripts:
	@echo "Syncing canonical scripts to extension directories..."
	@for ext in $(EXTENSIONS); do \
		scripts=$$($(MAKE) -s _print-scripts-$$ext) || \
			{ echo "Error: no script list target for extension '$$ext'"; exit 1; }; \
		if [ -z "$$scripts" ]; then \
			echo "Error: empty script list for extension '$$ext'"; exit 1; \
		fi; \
		for actual in $$(find "spex/extensions/$$ext/scripts" -type f 2>/dev/null); do \
			relpath=$${actual#spex/extensions/$$ext/scripts/}; \
			found=false; \
			for script in $$scripts; do \
				if [ "$$script" = "$$relpath" ]; then found=true; break; fi; \
			done; \
			if [ "$$found" = false ]; then \
				echo "Pruning obsolete: $$actual"; \
				rm "$$actual"; \
			fi; \
		done; \
		for script in $$scripts; do \
			dir=$$(dirname "spex/extensions/$$ext/scripts/$$script"); \
			mkdir -p "$$dir"; \
			cp "spex/scripts/$$script" "spex/extensions/$$ext/scripts/$$script" || \
				{ echo "Error: failed to copy $$script to extension '$$ext'"; exit 1; }; \
			case "$$script" in *.sh) chmod +x "spex/extensions/$$ext/scripts/$$script";; esac; \
		done; \
	done
	@echo "Script sync complete."

# Helper targets to print script lists per extension (used by sync-scripts)
_print-scripts-spex:
	@echo $(SCRIPTS_spex)
_print-scripts-spex-gates:
	@echo $(SCRIPTS_spex_gates)
_print-scripts-spex-collab:
	@echo $(SCRIPTS_spex_collab)
_print-scripts-spex-deep-review:
	@echo $(SCRIPTS_spex_deep_review)

sync-scripts-check:
	@echo "Checking extension scripts against canonical sources..."
	@fail=0; \
	for ext in $(EXTENSIONS); do \
		scripts=$$($(MAKE) -s _print-scripts-$$ext) || \
			{ echo "Error: no script list target for extension '$$ext'"; exit 1; }; \
		if [ -z "$$scripts" ]; then \
			echo "Error: empty script list for extension '$$ext'"; exit 1; \
		fi; \
		for script in $$scripts; do \
			canonical="spex/scripts/$$script"; \
			copy="spex/extensions/$$ext/scripts/$$script"; \
			if [ ! -f "$$canonical" ]; then \
				echo "BROKEN: canonical source missing: $$canonical (referenced in inventory)"; \
				fail=1; \
				continue; \
			fi; \
			if [ ! -f "$$copy" ]; then \
				echo "MISSING: $$copy (source: $$canonical)"; \
				fail=1; \
			elif ! diff -q "$$canonical" "$$copy" > /dev/null 2>&1; then \
				echo "STALE: $$copy differs from $$canonical"; \
				fail=1; \
			fi; \
		done; \
		for actual in $$(find "spex/extensions/$$ext/scripts" -type f 2>/dev/null); do \
			relpath=$${actual#spex/extensions/$$ext/scripts/}; \
			found=false; \
			for script in $$scripts; do \
				if [ "$$script" = "$$relpath" ]; then found=true; break; fi; \
			done; \
			if [ "$$found" = false ]; then \
				echo "UNEXPECTED: $$actual (not in inventory for extension '$$ext')"; \
				fail=1; \
			fi; \
		done; \
	done; \
	if [ $$fail -eq 1 ]; then \
		echo ""; \
		echo "Extension scripts are out of sync with canonical sources."; \
		echo "Run 'make sync-scripts' to fix."; \
		exit 1; \
	fi; \
	echo "All extension scripts are in sync."

check-upstream:
	cd spex && ./scripts/check-upstream-changes.sh

help:
	@echo "Available targets:"
	@echo "  validate            - Validate plugin manifests"
	@echo "  install             - Install plugin (adds marketplace, installs/updates plugin)"
	@echo "  uninstall           - Remove plugin and marketplace"
	@echo "  reinstall           - Full uninstall and reinstall"
	@echo "  migrate             - Remove old sdd plugin/marketplace (run automatically by install)"
	@echo "  test-hook           - Test the context hook"
	@echo "  test-install        - Integration test: install from local marketplace"
	@echo "  test-install-remote - Integration test: install from GitHub marketplace"
	@echo "  sync-scripts        - Copy canonical scripts from spex/scripts/ to extension directories"
	@echo "  sync-scripts-check  - Verify extension scripts match canonical sources (used by release)"
	@echo "  release             - Full release: validate, sync-check, test, tag, push, bump to dev"
	@echo "  check-upstream      - Check for upstream superpowers changes"
