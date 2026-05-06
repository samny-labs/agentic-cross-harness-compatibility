# Cross-harness agent setup recommendations
### GitHub Copilot + Cursor + opencode + Codex (primary) · Claude Code (secondary)
*May 2026*

---

## TL;DR

- **`AGENTS.md` is the only file all five tools read natively** — use it as your single source of project context. Directory-scoped `AGENTS.md` files also work universally for monorepos.
- **Prefer skills over ad hoc prompts or command files** for reusable workflows. Skills double as slash commands across all harnesses.
- **Custom agents and subagents do not automatically get skill context.** Some runtimes (e.g., Claude Code) support explicit skill preloading (e.g., a skills: field); others may not have a single dedicated knob but can still provide tools via the host/workspace setup. For reliability, include must-have tool knowledge and usage rules directly in the custom agent definition.
- **Avoid tool-specific names in skills** whenever possible. Describe intent and expected outcomes instead, and only add a compatibility mapping when explicit tool references are unavoidable.
- **For hooks `.claude/settings.json` is the best shared foundation** — Cursor, Copilot, and Claude Code all read them natively. Write hooks once, get coverage across three tools.

---

## Core principle

Use the smallest set of files that all five tools read natively, keep tool-specific config in tool-specific locations, and let unknown frontmatter keys be silently ignored rather than maintaining forks. Where four of five tools agree on a convention, that convention wins — even if Claude Code does it differently.

---

## 1. Project context — AGENTS.md is sufficient on its own

All five tools read `AGENTS.md` from the repo root natively. No additional wrapper files are needed.

**What belongs in AGENTS.md:**
- Tech stack and version numbers (tools cannot infer these)
- Build, test, and lint commands in code fences
- Non-obvious conventions and naming patterns
- Architecture decisions with brief rationale
- Hard constraints ("never commit to main directly")

**What does not belong in AGENTS.md:**
- Anything a linter or formatter already enforces
- Full API documentation (link to it instead)
- Step-by-step workflows (these go in skills)
- Agent-specific instructions

Keep it under 150 lines. Instruction adherence degrades above that threshold.

**Only add harness-specific instruction files if you genuinely need them.** `CLAUDE.md`, `.github/copilot-instructions.md`, `.cursor/rules/`, etc. add no value unless you have instructions that are meaningful to one tool and would be noise or actively wrong for the others. Cursor's `.cursor/rules/*.mdc` system supports glob-scoped and "agent-decides" rules — powerful, but Cursor-only. For cross-harness portability, express the same guidance in `AGENTS.md` or skills.

**Directory-scoped AGENTS.md files are supported across all five harnesses** and are the right solution for monorepos. Place an AGENTS.md in any subdirectory and it applies when the agent works in that area:

```
repo/
├── AGENTS.md               ← global: stack, commit format, architecture overview
├── frontend/
│   └── AGENTS.md           ← frontend-specific: component conventions, Tailwind rules
├── backend/
│   └── AGENTS.md           ← backend-specific: API patterns, DB conventions
└── packages/
    └── auth/
        └── AGENTS.md       ← package-specific: security constraints, never-touch rules
```

Deeper files take precedence over shallower ones. OpenAI's own main repository uses this pattern with 88 AGENTS.md files across subcomponents.

> [!WARNING]
> One caveat: **Copilot CLI currently discovers AGENTS.md files only along the path from the current working directory up to the git root**, not recursively across sibling directories. VS Code Copilot handles this with the `chat.useNestedAgentsMdFiles` setting (experimental). Codex, Cursor, Claude Code, and opencode all discover subdirectory files correctly.

---

## 2. Skills — use .agents/skills/ as the canonical path

The `.agents/skills/` directory is natively supported by four of the five primary tools:

| Path | Copilot | Cursor | opencode | Codex | Claude Code |
|---|---|---|---|---|---|
| `.agents/skills/` | ✓ | ✓ | ✓ | ✓ (native) | — |
| `.cursor/skills/` | — | ✓ (native) | — | — | — |
| `.claude/skills/` | ✓ | ✓ (compat) | ✓ (fallback) | — | ✓ (native) |
| `.github/skills/` | ✓ | — | — | — | — |

**Recommendation:** Use `.agents/skills/` as the canonical project-level skill location. It is the open standard path, native to your four primary tools, and the direction the ecosystem is converging on. For Claude Code compatibility, add a symlink:

```bash
ln -s .agents/skills .claude/skills
```

This gives you one set of skill files, all five tools reading them. No duplication.

```
.agents/skills/
├── pr-review/
│   └── SKILL.md
├── security-audit/
│   └── SKILL.md
└── api-conventions/
    └── SKILL.md
```

**Global personal skills** follow the same split:

| Tool | Global path |
|---|---|
| Codex | `~/.agents/skills/` or `~/.codex/skills/` |
| Copilot | `~/.copilot/skills/` or `~/.agents/skills/` |
| Cursor | `~/.cursor/skills/` or `~/.agents/skills/` |
| opencode | `~/.config/opencode/skills/` (also reads `~/.claude/skills/`) |
| Claude Code | `~/.claude/skills/` |

For personal skills shared across tools, `~/.agents/skills/` works for Codex, Copilot, and Cursor. Symlink it for the others:

```bash
ln -s ~/.agents/skills ~/.claude/skills
ln -s ~/.agents/skills ~/.config/opencode/skills
ln -s ~/.agents/skills ~/.cursor/skills
```

**SKILL.md structure:**

```yaml
---
name: pr-review
description: >
  Review a pull request for correctness, test coverage, and
  conventions. Use when the user says "review PR", "check this PR",
  or provides a PR number. Also triggers on /pr-review.
---

## Instructions
...
```

**Skill vs. inline knowledge decision rule:**

Use a skill for reusable knowledge the main agent discovers on demand across many tasks — coding conventions, workflow procedures, style guides. Inline the knowledge directly in an agent's system prompt body when the agent has a single fixed purpose and must have that knowledge available regardless of whether skill discovery works.

> [!WARNING]
> **Skills do not auto-trigger for custom agents** in any harness. An agent only sees skills you explicitly preload (Claude Code `skills:` field), configure per-agent permissions for (opencode `permission.skill`), or reference in Codex's `skills.config` TOML. For Copilot and Cursor agents there is no skill scoping mechanism — inline the knowledge in the agent body instead.

**Tool references in skill bodies:**

Tool names differ across harnesses. Prefer writing skills without explicit tool names (describe intent and expected result instead). If a skill must reference tools by name, add a compatibility block at the bottom:

```markdown
## Tool compatibility

| Claude Code  | Cursor        | opencode    | Copilot               | Codex         |
|--------------|---------------|-------------|-----------------------|---------------|
| TodoWrite    | (internal)    | update_plan | (internal state)      | (internal)    |
| Read(f)      | Read(f)       | read(f)     | readfile(f)           | read(f)       |
| Grep(p, d)   | Grep(p, d)    | grep(p, d)  | code_search(p)        | grep(p, d)    |
| Task         | Task          | @agent-name | see .github/agents/   | /agent spawn  |
```

**Slash commands:**

Codex (`.codex/commands/`), Claude Code (`.claude/commands/`), Cursor (plugin `commands/`), and opencode (`.opencode/commands/`) all support command files but do not cross-read. The practical solution is to write new reusable prompts as skills instead — skills surface as slash commands in all five tools and support `$ARGUMENTS` substitution.

---

## 3. Agents — portable core, tool-specific wiring

Agent definition files differ in format and location across all five harnesses. Write the portable core once and accept that the config wrapper is per-tool.

**Portable fields (work across all five):**

| Field | Notes |
|---|---|
| `name` | Lowercase hyphens. Filename without extension. |
| `description` | The routing signal. Write with "use when…" phrasing. This is the most important field. |
| System prompt body | Plain markdown prose. Keep tool-specific mechanics out of here. |

**File locations and formats:**

| Tool | Location | Format |
|---|---|---|
| Copilot | `.github/agents/*.agent.md` | Markdown + YAML frontmatter |
| Cursor | `.cursor/agents/*.md` (or via plugins) | Markdown + YAML frontmatter |
| opencode | `.opencode/agents/*.md` | Markdown + YAML frontmatter |
| Claude Code | `.claude/agents/*.md` | Markdown + YAML frontmatter |
| Codex | `.codex/agents/*.toml` | **TOML** (not markdown) |

Codex is the outlier — it uses standalone TOML files with `instructions` as a string field rather than a markdown body. The persona text is the same; only the container format differs. Cursor also supports distributing agents via its plugin system (marketplace or team marketplace).

**Maintain one shared source of truth** for the persona and system prompt in `docs/agents/security-reviewer.md` (plain markdown, not picked up by any tool). Copy into each tool's format — the body is identical; only the frontmatter/wrapper changes.

**When to use a subagent:**

Use a subagent when the work would pollute the main conversation context (reading many files, running searches), when you need parallel execution, when the task requires different tool permissions than the parent, or when you want a different model or effort level for a subtask. Do not use a subagent when the task needs conversation history, is small and fast, or needs intermediate reasoning to be visible.

---

## 4. Hooks and plugins

All five tools support some form of event-driven automation, but with different formats and maturity levels.

### GitHub Copilot hooks (preview, VS Code)

Copilot gained hooks in VS Code in April 2026 (preview). 8 lifecycle events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`.

Hook files are JSON in `.github/hooks/*.json`. Copilot also reads `.claude/settings.json` as a hook source by default — so hooks written for Claude Code are picked up automatically, with two caveats:

- **Tool names differ**: Claude Code's `Write`/`Edit` vs Copilot's `create_file`/`replace_string_in_file`.
- **Matchers are currently ignored**: all hooks fire on every matching event regardless of matcher value.

Hooks can also be scoped per custom agent via the `hooks:` field in `.agent.md` frontmatter (preview).

### Codex

Codex does not have Claude Code-style lifecycle hooks. Automation is handled through MCP, skills, and external CI/CD (pre-commit hooks, linters, GitHub Actions). Codex automations (app-level scheduled runs) can invoke skills on a cadence.

### Claude Code hooks

Shell scripts registered in `.claude/settings.json` under `hooks`. The most mature implementation — `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `Notification`, `UserPromptSubmit`, `PreCompact`, `SessionStart`, `SessionEnd`, and more.

### Cursor hooks

JSON-based hook definitions in `.cursor/hooks.json` (project) or `~/.cursor/hooks.json` (user). The most comprehensive event set of any harness: `sessionStart`, `sessionEnd`, `preToolUse`, `postToolUse`, `postToolUseFailure`, `subagentStart`, `subagentStop`, `beforeShellExecution`, `afterShellExecution`, `beforeMCPExecution`, `afterMCPExecution`, `beforeReadFile`, `afterFileEdit`, `beforeSubmitPrompt`, `preCompact`, `stop`, `afterAgentResponse`, `afterAgentThought`, plus Tab-specific hooks (`beforeTabFileRead`, `afterTabFileEdit`). Cursor also natively reads `.claude/settings.json` hooks for cross-tool compatibility. Supports both command-based and prompt-based (LLM-evaluated) hooks.

### opencode plugins

TypeScript modules in `.opencode/plugin/` subscribing to 25+ internal events via an SDK. More powerful than shell-script hooks — can also register custom tools — but requires TypeScript rather than shell scripts.

### Practical approach

For Copilot + Cursor + Claude Code hook sharing, `.claude/settings.json` is the best shared foundation — all three read it natively. Keep shell scripts in a shared `scripts/` directory.

For Copilot-native hooks, use `.github/hooks/*.json` — committed to the repo, reviewable in PRs.

For Cursor-native hooks with full feature support (prompt-based hooks, `failClosed`, Tab hooks), use `.cursor/hooks.json`.

For opencode, implement separately as a TypeScript plugin. The shell script logic can be reused; only the wiring differs.

Codex doesn't have an equivalent lifecycle hook system — use MCP, skills, and external CI/CD for comparable automation.

---

## 5. MCP servers — configure globally, available everywhere

All five tools support MCP. Configure servers globally rather than per-agent.

| Tool | MCP config location |
|---|---|
| Codex | `~/.codex/config.toml` under `[mcp]` (TOML format) |
| Copilot | VS Code settings or org-level MCP allowlist |
| Cursor | `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global) |
| opencode | `opencode.json` under `mcpServers` |
| Claude Code | `.claude/settings.json` under `mcpServers` |

MCP is the right layer for external tool integrations (databases, APIs, Figma, GitHub). Skills are the right layer for teaching an agent *how to use* those tools effectively. They solve different problems and compose well together.

---

## 6. Recommended repo structure

```
repo/
├── AGENTS.md                              ← universal project context
├── .agents/
│   └── skills/                            ← canonical skill location (Copilot + Cursor + opencode + Codex)
│       ├── pr-review/SKILL.md
│       └── security-audit/SKILL.md
├── .claude/
│   ├── skills -> ../.agents/skills        ← symlink for Claude Code compatibility
│   ├── agents/                            ← Claude Code agent definitions
│   │   └── security-reviewer.md
│   └── settings.json                      ← hooks (read by Claude Code + Copilot + Cursor)
├── .cursor/
│   ├── agents/                            ← Cursor agent definitions
│   │   └── security-reviewer.md
│   ├── hooks.json                         ← Cursor-native hooks (full feature set)
│   ├── mcp.json                           ← Cursor MCP server config
│   └── rules/                             ← Cursor rules (.mdc files, optional)
├── .github/
│   ├── agents/
│   │   └── security-reviewer.agent.md    ← Copilot agent definition
│   └── hooks/                             ← Copilot-native hooks (optional)
├── .opencode/
│   ├── agents/                            ← opencode agent definitions
│   │   └── security-reviewer.md
│   └── plugin/                            ← opencode TypeScript plugins
├── .codex/
│   └── agents/                            ← Codex agent definitions (TOML)
│       └── security-reviewer.toml
├── scripts/                               ← shared shell scripts for hooks
│   ├── format.sh
│   └── block-dangerous.sh
└── docs/
    └── agents/                            ← shared source of truth for agent personas
        └── security-reviewer.md           ← not picked up by any tool; human reference
```

---

## 7. Summary: what is and isn't portable

| Artifact | Portability | Action |
|---|---|---|
| `AGENTS.md` content | Universal | One file, all five tools read it natively |
| Directory-scoped `AGENTS.md` | Universal | Subdirectory files work in all five; Copilot CLI has a sibling-discovery limitation |
| `SKILL.md` content (prose) | Universal | Write once in `.agents/skills/`; symlink `.claude/skills/` for Claude Code; Cursor reads `.agents/skills/` natively |
| Tool names in skill bodies | Needs translation table | Add compatibility block to skill |
| Slash command bodies | Portable content, not discovery | Promote to skills for cross-harness reach |
| Agent name + description | Universal | Same values across all agent files |
| Agent system prompt body | Universal | Copy verbatim; Codex wraps in TOML instead of markdown frontmatter |
| Agent config (tools, permissions, model) | Tool-specific | Different frontmatter/format per tool; unknown keys silently ignored in markdown-based tools |
| Agent skill preloading | Not portable | Claude Code: `skills:` field. opencode: `permission.skill`. Codex: `skills.config` TOML. Copilot/Cursor: inline in agent body |
| Hooks | Mostly portable | Cursor + Copilot read `.claude/settings.json` natively; opencode needs a plugin; Codex has no lifecycle hooks |
| MCP server config | Same concept, different formats | Configure per-tool pointing at the same servers |
| `.agents/` directory standard | 4 of 5 tools | Copilot + Cursor + opencode + Codex native; Claude Code needs symlink |
