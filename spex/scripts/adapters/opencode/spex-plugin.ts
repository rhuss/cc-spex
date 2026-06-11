/**
 * spex-plugin.ts - OpenCode plugin for spex enforcement
 *
 * Subscribes to tool.execute.before events to enforce spex workflow gates:
 * - Skill-first loading (blocks non-Skill tools when command pending)
 * - Ship pipeline stage ordering
 * - Teams enforcement (blocks background agents during implementation)
 * - Verify-before-commit reminder
 *
 * Calls shared POSIX shell functions via child_process.execSync for
 * enforcement decisions, keeping logic in sync with Claude Code and Codex
 * adapters.
 *
 * Install: copy to .opencode/plugins/spex-plugin.ts
 */

import { execSync } from "child_process";
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

// Resolve the shared scripts directory relative to this plugin's installed location.
// When installed by spex-init.sh, this plugin is copied to .opencode/plugins/.
// The shared scripts live at <plugin-root>/scripts/hooks/shared/.
// We find plugin-root by reading .specify/init-options.json or falling back to
// searching for the spex directory structure.
function findSharedDir(): string | null {
  const cwd = process.cwd();

  // Try to find plugin root from .specify/init-options.json
  const initOptions = join(cwd, ".specify", "init-options.json");
  if (existsSync(initOptions)) {
    try {
      const opts = JSON.parse(readFileSync(initOptions, "utf-8"));
      if (opts.plugin_root) {
        const shared = join(opts.plugin_root, "scripts", "hooks", "shared");
        if (existsSync(shared)) return shared;
      }
    } catch {
      // fall through
    }
  }

  // Search upward for spex directory structure
  const candidates = [
    join(cwd, "spex", "scripts", "hooks", "shared"),
    join(cwd, "..", "spex", "scripts", "hooks", "shared"),
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }

  return null;
}

function runShared(
  sharedDir: string,
  script: string,
  args: string[]
): string | null {
  const scriptPath = join(sharedDir, script);
  if (!existsSync(scriptPath)) return null;

  try {
    const escaped = args.map((a) => `'${a.replace(/'/g, "'\\''")}'`).join(" ");
    const result = execSync(`sh '${scriptPath}' ${escaped}`, {
      encoding: "utf-8",
      timeout: 5000,
      stdio: ["pipe", "pipe", "pipe"],
    });
    return result.trim();
  } catch (e) {
    console.error(`WARNING: ${script} error:`, e);
    return null;
  }
}

function parseResult(result: string | null): [string, string | null] {
  if (!result) return ["allow", null];
  if (result.startsWith("deny:")) return ["deny", result.slice(5)];
  if (result.startsWith("context:")) return ["context", result.slice(8)];
  return ["allow", null];
}

function markerPath(prefix: string, sessionId: string): string {
  return join(tmpdir(), `.claude-${prefix}-${sessionId}`);
}

// Session ID for OpenCode (use PID as fallback since OpenCode
// doesn't expose a session_id env var)
function getSessionId(): string {
  return process.env.OPENCODE_SESSION_ID || `opencode-${process.pid}`;
}

/**
 * OpenCode plugin export.
 *
 * Registers a tool.execute.before handler that enforces spex gates.
 */
export default {
  name: "spex",
  version: "1.0.0",

  register(api: any) {
    api.on("tool.execute.before", (event: any) => {
      const toolName: string = event.tool || event.name || "";
      const toolInput: Record<string, any> = event.input || event.args || {};
      const cwd = process.cwd();
      const sessionId = getSessionId();

      // Side effect: clear skill-pending marker when Skill tool invoked
      if (toolName === "Skill") {
        const marker = markerPath("spex-skill-pending", sessionId);
        try {
          unlinkSync(marker);
        } catch {
          // marker didn't exist
        }
      }

      // Side effect: clean up completed ship state
      const stateFile = join(cwd, ".specify", ".spex-state");
      if (existsSync(stateFile)) {
        try {
          const state = JSON.parse(readFileSync(stateFile, "utf-8"));
          if (state.status === "completed" && state.stage === "done") {
            unlinkSync(stateFile);
          }
        } catch {
          // ignore parse errors
        }
      }

      const sharedDir = findSharedDir();
      if (!sharedDir) {
        // No shared scripts found, fail open
        return;
      }

      // Gate 1: Skill gate (short-circuits)
      const skillResult = runShared(sharedDir, "skill-gate.sh", [
        toolName,
        sessionId,
      ]);
      const [skillType, skillReason] = parseResult(skillResult);
      if (skillType === "deny") {
        throw new Error(skillReason || "Skill gate denied");
      }

      // Gate 2: Teams enforcement
      const teamsResult = runShared(sharedDir, "teams-gate.sh", [
        toolName,
        JSON.stringify(toolInput),
        cwd,
      ]);
      const [teamsType, teamsContent] = parseResult(teamsResult);
      if (teamsType === "deny") {
        throw new Error(teamsContent || "Teams gate denied");
      }

      // Gate 3: Ship pipeline
      const skillName =
        toolName === "Skill" ? (toolInput.skill || "") : "";
      const shipResult = runShared(sharedDir, "stage-gate.sh", [
        toolName,
        skillName,
        stateFile,
      ]);
      const [shipType, shipContent] = parseResult(shipResult);
      if (shipType === "deny") {
        throw new Error(shipContent || "Stage gate denied");
      }
      // Context injection for ship pipeline is advisory on OpenCode
      // (no mechanism to inject additionalContext from plugin)

      // Gate 4: Verification reminder (advisory, logged to console)
      const command =
        toolName === "Bash" ? (toolInput.command || "") : "";
      const verifyResult = runShared(sharedDir, "verify-gate.sh", [
        toolName,
        command,
        sessionId,
        cwd,
      ]);
      const [verifyType, verifyContent] = parseResult(verifyResult);
      if (verifyType === "context" && verifyContent) {
        console.warn(`[spex] ${verifyContent}`);
      }
    });
  },
};
