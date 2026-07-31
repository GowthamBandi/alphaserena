# Security Tooling Setup — AlphaSerena

Date: 2026-07-29
Mission: install + configure official Claude Security tooling for continuous security
reviews of this repository. **No application source code was modified. Nothing was
committed or deployed.**

---

## 1. Environment (Phase 1 — as found, before changes)

| Item | State |
|---|---|
| Claude Code version | **2.1.212** |
| Plugin system | Available (`claude plugin` CLI: install / list / details / validate / marketplace …) |
| Marketplaces configured | `claude-plugins-official` (GitHub `anthropics/claude-plugins-official` — the official Anthropic marketplace) and `ui-ux-pro-max-skill` (third-party) |
| Plugins already installed | `superpowers@claude-plugins-official` 6.2.0, `ui-ux-pro-max@ui-ux-pro-max-skill` 2.11.0 (both user scope, enabled) |
| Hooks | Only plugin-provided (superpowers SessionStart). No custom hooks in user or project settings |
| MCP servers | One user-level server: `claude.ai HyperFrames by HeyGen` (needs auth). No project `.mcp.json` |
| Existing security configuration | None. Built-in `/security-review` command available; no security plugins, no semgrep binary on PATH |
| Project `.claude/` | `settings.local.json` (permission allowlist only) + copied design skills under `.claude/skills/` |

## 2. Installations performed (Phases 2–3)

Both official plugins exist in `claude-plugins-official` and installed without errors:

```
claude plugin install claude-security@claude-plugins-official   → ✅ v0.10.0 (user scope)
claude plugin install semgrep@claude-plugins-official           → ✅ v2.1.4  (user scope)
```

### claude-security 0.10.0 (Anthropic)
Deep vulnerability scanning run inside the Claude Code session at a chosen effort
tier; every finding is challenged by an independent verifier panel before being
reported; surviving findings can be turned into patch files (verified by a panel of
agents) that **you** apply — the plugin never commits, pushes, or auto-applies.

Components: 1 skill (`claude-security` — a menu of three jobs), 7 agents
(scan-inventory / scan-researcher / scan-verifier / patch-generator / patch-verifier /
explore / claude-security), 1 harness hook, a `scan` workflow. ~642 always-on tokens.

### Semgrep Guardian 2.1.4 (Semgrep, via the official marketplace)
Real-time guardrail: hooks on `PreToolUse` / `PostToolUse` / `PostToolBatch` /
`SessionStart` / `SessionEnd` scan **agent-generated code as it is written**, plus a
`guardian` MCP server. Ships its own self-contained scanner binaries per platform
(`hook-windows-amd64.exe` verified runnable) — no separate semgrep CLI required for
the plugin itself.

## 3. Verification (Phase 4)

- `claude plugin list` → both plugins **installed and enabled** (user scope), alongside the pre-existing two.
- `claude plugin details <name>` → full component inventories resolved for both (shown above).
- `claude plugin validate <cache dir>` → **Validation passed** for both manifests.
- Guardian hook binary executed successfully (`--help`, exit 0); `.in_use` session markers present.
- No installation errors at any step.

## 4. Repository configuration (Phase 5)

- Added to `.claude/settings.local.json` (repo-local, **not** checked in — git-ignored by Claude Code convention):
  ```json
  "enabledPlugins": {
    "claude-security@claude-plugins-official": true,
    "semgrep@claude-plugins-official": true
  }
  ```
  This pins both plugins on for this repository even if their user-scope state changes.
- No application code, build logic (`pubspec.yaml`, Gradle, Xcode), or committed files were touched.

## 5. Validation scan (Phase 6)

- **Plugin-driven scan:** the `claude-security` skill loads in a *new* session (plugins
  installed mid-session activate on restart), and this environment's permission
  classifier blocks launching a nested headless `claude -p` session — so the in-plugin
  scan is validated as ready but must be run interactively (see Commands below).
- **Direct Semgrep scan (executed):** `uvx semgrep scan --config auto lib/`
  - Semgrep CLI 1.172.0 via `uvx` (uv is installed).
  - ✅ Scan completed: **51 rules run · 136 files scanned · ~100% parsed · 0 findings · 0 errors** (exit 0).
  - Findings pipeline confirmed working; result for this codebase: **no findings** at this rule set.
- Patch suggestions: supported by claude-security ("Suggest patches" job → patch files
  on disk, verified by an agent panel, applied manually). **No fixes were applied**, per mission.

## 6. Available commands

| Command | What it does |
|---|---|
| `/claude-security` (in a new session) | Menu: **Scan codebase** (whole repo or scoped) · **Scan changes** (branch/PR diff or one commit) · **Suggest patches** (findings → verified patch files, applied by you). Works best in auto mode (`claude --permission-mode auto`). Reports land in `CLAUDE-SECURITY-<timestamp>/` at the repo root. |
| `/security-review` | Built-in Claude Code review of pending changes on the current branch. |
| Semgrep Guardian | No command — automatic. Its hooks scan code as Claude writes/edits it and flag vulnerabilities in real time; `install-mfw` skill available to install its CLI wrapper. |
| `claude plugin update claude-security` / `semgrep` | Keep the tools current. |

## 7. Limitations

- **Restart needed**: plugin skills/hooks installed mid-session activate on the next Claude Code session.
- **Dart coverage in Semgrep is thin**: `--config auto` ran generic/multi-language + JSON rules (51) — Semgrep has no first-class Dart language rules, so the direct-CLI scan mainly covers secrets/generic patterns and config files. The claude-security plugin (LLM-driven) is the primary deep scanner for this Flutter codebase.
- claude-security runs **in-session under your permissions** (no isolation layer) — intended for scanning your own code; use sandbox-runtime for untrusted repos.
- Guardian hooks target agent-generated code (Write/Edit/Bash), not a full-repo audit.
- Nested headless sessions are blocked here, so scheduled/automated in-plugin scans would need CI or a user-launched session.
- Backend security surface (Firestore rules, Cloud Functions) lives in the **trainersHQ** repo — scans here do not cover it.

## 8. Recommendations

1. Next session, run `/claude-security` → **Scan codebase** at a low tier once as a baseline; thereafter use **Scan changes** before merges.
2. Add `CLAUDE-SECURITY-*/` to `.gitignore` so scan reports are never committed (left untouched per "no repo file changes" scope).
3. Run the same setup in the **trainersHQ** repo — that's where the security-critical surface (rules, payment CFs, `getMyTraining`) lives.
4. Consider `semgrep login` (free registry rules) and a Semgrep CI step if Dart rule coverage improves.
5. Periodically `claude plugin update` both plugins.
