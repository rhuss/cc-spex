.PHONY: validate validate-contracts check-contract-deps materialize materialize-codex validate-materialized test-unit test-install-claude test-install-codex test-install-combined test-lifecycle test-worktree-lifecycle test-recovery test-progress test-teams test release-check install install-codex-local uninstall reinstall check-upstream test-hook test-install test-install-remote release migrate sync-scripts sync-scripts-check help

MARKETPLACE := spex-plugin-development
PLUGIN := spex@$(MARKETPLACE)

CONTRACT_SCHEMAS := $(sort $(wildcard specs/047-codex-plugin-support/contracts/*.schema.json))
JSON_SCHEMA_VALIDATOR ?= check-jsonschema

# Legacy names (pre-3.0.0)
OLD_MARKETPLACE := sdd-plugin-development
OLD_PLUGIN := sdd@$(OLD_MARKETPLACE)

validate:
	claude plugin validate ./
	claude plugin validate ./spex/

check-contract-deps:
	@command -v "$(word 1,$(JSON_SCHEMA_VALIDATOR))" >/dev/null 2>&1 || { \
		echo "Error: $(JSON_SCHEMA_VALIDATOR) is required for JSON Schema validation." >&2; \
		echo "Install it with: python3 -m pip install check-jsonschema" >&2; \
		exit 1; \
	}

validate-contracts: check-contract-deps
	@test -n "$(CONTRACT_SCHEMAS)" || { echo "Error: no contract schemas found" >&2; exit 1; }
	$(JSON_SCHEMA_VALIDATOR) --check-metaschema $(CONTRACT_SCHEMAS)

materialize:
	@test -n "$(HARNESS)" || { echo "Error: HARNESS is required (claude, codex, or opencode)" >&2; exit 2; }
	@case "$(HARNESS)" in claude|codex|opencode) ;; *) echo "Error: HARNESS must be claude, codex, or opencode" >&2; exit 2;; esac
	@test -n "$(OUT)" || { echo "Error: OUT is required and must be an absolute directory path" >&2; exit 2; }
	@case "$(OUT)" in /*) ;; *) echo "Error: OUT must be an absolute directory path" >&2; exit 2;; esac
	@./spex/scripts/spex-materialize-plugin.sh --harness "$(HARNESS)" --output "$(OUT)"

materialize-codex:
	@test -n "$(CODEX_MARKETPLACE_ROOT)" || { echo "Error: CODEX_MARKETPLACE_ROOT is required" >&2; exit 2; }
	@case "$(CODEX_MARKETPLACE_ROOT)" in /*) ;; *) echo "Error: CODEX_MARKETPLACE_ROOT must be an absolute directory path" >&2; exit 2;; esac
	@test "$(CODEX_MARKETPLACE_ROOT)" != "/" || { echo "Error: refusing to use filesystem root as CODEX_MARKETPLACE_ROOT" >&2; exit 2; }
	@test -d "$(CODEX_MARKETPLACE_ROOT)" || { echo "Error: CODEX_MARKETPLACE_ROOT must already exist" >&2; exit 2; }
	@root=$$(cd "$(CODEX_MARKETPLACE_ROOT)" && pwd -P); repo=$$(pwd -P); \
	case "$$root/" in "$$repo/"*) echo "Error: CODEX_MARKETPLACE_ROOT must be outside the repository" >&2; exit 2;; esac; \
	mkdir -p "$$root/.agents/plugins" "$$root/plugins"; \
	cp .codex-plugin/marketplace.json "$$root/.agents/plugins/marketplace.json"; \
	./spex/scripts/spex-materialize-plugin.sh --harness codex --output "$$root/plugins/codex"

install-codex-local:
	@test -n "$(CODEX_USER_HOME)" || { echo "Error: CODEX_USER_HOME is required for an isolated install" >&2; exit 2; }
	@test -n "$(CODEX_LOCAL_HOME)" || { echo "Error: CODEX_LOCAL_HOME is required for an isolated install" >&2; exit 2; }
	@case "$(CODEX_USER_HOME)" in /*) ;; *) echo "Error: CODEX_USER_HOME must be an absolute directory path" >&2; exit 2;; esac
	@case "$(CODEX_LOCAL_HOME)" in /*) ;; *) echo "Error: CODEX_LOCAL_HOME must be an absolute directory path" >&2; exit 2;; esac
	@test "$(CODEX_USER_HOME)" != "/" -a "$(CODEX_LOCAL_HOME)" != "/" || { echo "Error: refusing to use filesystem root as a Codex home" >&2; exit 2; }
	@test -d "$(CODEX_USER_HOME)" || { echo "Error: CODEX_USER_HOME must already exist" >&2; exit 2; }
	@test -d "$(CODEX_LOCAL_HOME)" || { echo "Error: CODEX_LOCAL_HOME must already exist" >&2; exit 2; }
	@user_home=$$(cd "$(CODEX_USER_HOME)" && pwd -P); local_home=$$(cd "$(CODEX_LOCAL_HOME)" && pwd -P); repo=$$(pwd -P); \
	case "$$user_home/" in "$$repo/"*) echo "Error: CODEX_USER_HOME must be outside the repository" >&2; exit 2;; esac; \
	case "$$local_home/" in "$$repo/"*) echo "Error: CODEX_LOCAL_HOME must be outside the repository" >&2; exit 2;; esac
	@command -v codex >/dev/null 2>&1 || { echo "Error: codex CLI is required" >&2; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }
	@codex plugin marketplace add --help >/dev/null 2>&1 && codex plugin add --help >/dev/null 2>&1 || \
		{ echo "Error: installed Codex CLI does not support personal plugin marketplaces" >&2; exit 1; }
	@$(MAKE) --no-print-directory materialize-codex CODEX_MARKETPLACE_ROOT="$(CODEX_MARKETPLACE_ROOT)"
	@set -e; \
	marketplace=$$(jq -er '.name | select(length > 0)' "$(CODEX_MARKETPLACE_ROOT)/.agents/plugins/marketplace.json"); \
	plugin=$$(jq -er '.name | select(length > 0)' "$(CODEX_MARKETPLACE_ROOT)/plugins/codex/.codex-plugin/plugin.json"); \
	HOME="$(CODEX_USER_HOME)" CODEX_HOME="$(CODEX_LOCAL_HOME)" \
		codex plugin marketplace add "$(CODEX_MARKETPLACE_ROOT)" --json | jq -e .; \
	HOME="$(CODEX_USER_HOME)" CODEX_HOME="$(CODEX_LOCAL_HOME)" \
		codex plugin add "$$plugin@$$marketplace" --json | jq -e .

validate-materialized:
	@test -n "$(CLAUDE_OUT)" || { echo "Error: CLAUDE_OUT is required and must be an absolute directory path" >&2; exit 2; }
	@test -n "$(CODEX_OUT)" || { echo "Error: CODEX_OUT is required and must be an absolute directory path" >&2; exit 2; }
	@case "$(CLAUDE_OUT)" in /*) ;; *) echo "Error: CLAUDE_OUT must be an absolute directory path" >&2; exit 2;; esac
	@case "$(CODEX_OUT)" in /*) ;; *) echo "Error: CODEX_OUT must be an absolute directory path" >&2; exit 2;; esac
	@test "$(CLAUDE_OUT)" != "$(CODEX_OUT)" || { echo "Error: CLAUDE_OUT and CODEX_OUT must be different directories" >&2; exit 2; }
	@./spex/scripts/spex-validate-materialized.sh --harness claude --input "$(CLAUDE_OUT)"
	@./spex/scripts/spex-validate-materialized.sh --harness codex --input "$(CODEX_OUT)"

test-unit: validate-contracts
	@set -e; \
	tests=$$(find tests/unit -maxdepth 1 -type f -name 'test_*.sh' | LC_ALL=C sort); \
	test -n "$$tests" || { echo "Error: no unit test scripts found" >&2; exit 1; }; \
	for test_script in $$tests; do \
		echo "Running $$test_script..."; \
		JSON_SCHEMA_VALIDATOR="$(JSON_SCHEMA_VALIDATOR)" bash "$$test_script"; \
	done

test-install-claude:
	@tests/integration/test_install_claude.sh

test-install-codex:
	@tests/integration/test_install_codex.sh

test-install-combined:
	@tests/integration/test_install_combined.sh

test-lifecycle:
	@tests/integration/test_worktree_lifecycle.sh

test-worktree-lifecycle: test-lifecycle

test-recovery:
	@tests/integration/test_ship_recovery.sh

test-progress:
	@tests/integration/test_codex_progress.sh

test-teams:
	@tests/integration/test_codex_teams.sh
	@tests/integration/test_codex_teams_fallback.sh

test: test-unit test-lifecycle test-recovery test-progress test-teams test-install-claude test-install-codex test-install-combined

release-check: sync-scripts-check test
	@stage_root=$$(mktemp -d "$${TMPDIR:-/tmp}/spex-release-check.XXXXXX"); \
	trap 'rm -rf -- "$$stage_root"' EXIT; \
	./spex/scripts/spex-materialize-plugin.sh --harness claude --output "$$stage_root/claude" >/dev/null; \
	./spex/scripts/spex-materialize-plugin.sh --harness codex --output "$$stage_root/codex" >/dev/null; \
	./spex/scripts/spex-validate-materialized.sh --harness claude --input "$$stage_root/claude" >/dev/null; \
	./spex/scripts/spex-validate-materialized.sh --harness codex --input "$$stage_root/codex" >/dev/null; \
	echo "Release check passed without creating a tag."

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

release: validate release-check
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
	echo "Updating version to $$VERSION across Claude and Codex distributions, setup, and bundle inventories..."; \
	tmp=$$(mktemp); \
	jq --arg v "$$VERSION" '(.plugins[] | select(.name == "spex")).version = $$v' .claude-plugin/marketplace.json > "$$tmp" && mv "$$tmp" .claude-plugin/marketplace.json; \
	tmp=$$(mktemp); \
	jq --arg v "$$VERSION" '.version = $$v' spex/.claude-plugin/plugin.json > "$$tmp" && mv "$$tmp" spex/.claude-plugin/plugin.json; \
	tmp=$$(mktemp); \
	jq --arg v "$$VERSION" '.version = $$v' plugins/codex/.codex-plugin/plugin.json > "$$tmp" && mv "$$tmp" plugins/codex/.codex-plugin/plugin.json; \
	sed -i.bak "s/^  version: \".*\"/  version: \"$$VERSION\"/" spex/setup.yml && rm -f spex/setup.yml.bak; \
	sed -i.bak "s/^  version: \".*\"/  version: \"$$VERSION\"/" spex/bundle.yml && rm -f spex/bundle.yml.bak; \
	sed -i.bak "s/^      version: \".*\"/      version: \"$$VERSION\"/" spex/bundle.yml && rm -f spex/bundle.yml.bak; \
	echo "$$VERSION" > spex/VERSION; \
	git add VERSION spex/VERSION .claude-plugin/marketplace.json spex/.claude-plugin/plugin.json plugins/codex/.codex-plugin/plugin.json spex/setup.yml spex/bundle.yml; \
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
SCRIPTS_spex_state_worktree := spex-ship-state.py spex-ship-state.sh spex-worktree-cwd.sh
SCRIPTS_spex := spex-finish-context.sh spex-flow-state.sh spex-ship-statusline.sh $(SCRIPTS_spex_state_worktree)
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
		for actual in $$(find "spex/extensions/$$ext/scripts" -type f 2>/dev/null | LC_ALL=C sort); do \
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
		for actual in $$(find "spex/extensions/$$ext/scripts" -type f 2>/dev/null | LC_ALL=C sort); do \
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
	@echo "  validate-contracts  - Validate feature contracts against their JSON metaschema"
	@echo "  materialize         - Stage a harness plugin (requires HARNESS and absolute OUT)"
	@echo "  materialize-codex   - Build an external local Codex marketplace (requires CODEX_MARKETPLACE_ROOT)"
	@echo "  validate-materialized - Validate staged Claude and Codex outputs (requires CLAUDE_OUT and CODEX_OUT)"
	@echo "  test-unit           - Validate contracts and run all shell unit tests"
	@echo "  test                - Run unit, lifecycle, recovery, Teams, progress, and install suites"
	@echo "  test-install-claude - Run the isolated Claude installation suite"
	@echo "  test-install-codex  - Run the isolated Codex installation suite"
	@echo "  test-install-combined - Run the combined harness installation suite"
	@echo "  release-check       - Run all pre-tag release gates without tagging"
	@echo "  install-codex-local - Materialize and install Codex into explicit isolated home paths"
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
