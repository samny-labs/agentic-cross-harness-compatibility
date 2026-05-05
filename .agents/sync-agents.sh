#!/usr/bin/env bash
set -euo pipefail

# sync-agents.sh — Generate tool-specific agent files from shared definitions.
#
# Source: .agents/agents/*.md (markdown + YAML frontmatter)
# Targets: .github/agents/   (Copilot — .agent.md)
#          .opencode/agents/  (opencode — .md)
#          .claude/agents/    (Claude Code — .md)
#          .codex/agents/     (Codex — .toml)
#          .cursor/agents/    (Cursor — .md)
#
# Usage:
#   ./scripts/sync-agents.sh              # sync all agents
#   ./scripts/sync-agents.sh --dry-run    # show what would be written
#   ./scripts/sync-agents.sh --clean      # remove generated files before syncing

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SOURCE_DIR="${REPO_ROOT}/.agents/agents"
GENERATED_MARKER="# AUTO-GENERATED from .agents/agents/ — do not edit directly."

DRY_RUN=false
CLEAN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --clean)   CLEAN=true ;;
    --help|-h)
      echo "Usage: sync-agents.sh [--dry-run] [--clean]"
      echo "  --dry-run  Print what would be written without writing"
      echo "  --clean    Remove previously generated agent files before syncing"
      exit 0
      ;;
  esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "No source directory found at ${SOURCE_DIR}" >&2
  echo "Create .agents/agents/*.md files first." >&2
  exit 1
fi

# --- helpers ---

write_file() {
  local path="$1"
  local content="$2"

  if $DRY_RUN; then
    echo "[dry-run] would write: $path"
    return
  fi

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  echo "  wrote: $path"
}

# Split a markdown file into frontmatter (without ---) and body.
# Sets two global variables: FM and BODY.
parse_md() {
  local file="$1"
  local in_fm=false
  local fm_done=false
  FM=""
  BODY=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ! $fm_done; then
      if [[ "$line" == "---" ]]; then
        if $in_fm; then
          fm_done=true
        else
          in_fm=true
        fi
        continue
      fi
      if $in_fm; then
        FM+="${line}"$'\n'
      fi
    else
      BODY+="${line}"$'\n'
    fi
  done < "$file"

  # Trim trailing newlines from body
  BODY="${BODY%$'\n'}"
}

# Extract a YAML value by key (simple single-line or folded scalar).
# Handles: key: value / key: "value" / key: >- multiline
yaml_val() {
  local key="$1"
  local yaml="$2"
  local val

  # Try single-line first
  val=$(echo "$yaml" | grep -E "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//')

  if [[ -z "$val" ]]; then
    return
  fi

  # If it's a block scalar indicator (> or |), read subsequent indented lines
  if [[ "$val" == ">"* ]] || [[ "$val" == "|"* ]]; then
    val=""
    local capture=false
    while IFS= read -r line; do
      if $capture; then
        if [[ "$line" =~ ^[[:space:]] ]]; then
          val+="$(echo "$line" | sed 's/^[[:space:]]*//')"$' '
        else
          break
        fi
      fi
      if echo "$line" | grep -qE "^${key}:"; then
        capture=true
      fi
    done <<< "$yaml"
    val="${val% }"
  fi

  echo "$val"
}

# --- clean ---

if $CLEAN; then
  echo "Cleaning generated agent files..."
  for dir in ".github/agents" ".opencode/agents" ".claude/agents" ".codex/agents" ".cursor/agents"; do
    target="${REPO_ROOT}/${dir}"
    if [[ -d "$target" ]]; then
      while IFS= read -r -d '' f; do
        if head -1 "$f" | grep -q "AUTO-GENERATED"; then
          if $DRY_RUN; then
            echo "[dry-run] would remove: $f"
          else
            rm "$f"
            echo "  removed: $f"
          fi
        fi
      done < <(find "$target" -maxdepth 1 -type f \( -name '*.md' -o -name '*.toml' \) -print0)
    fi
  done
  if $DRY_RUN; then
    echo "[dry-run] clean complete."
  fi
fi

# --- sync ---

count=0

for src in "${SOURCE_DIR}"/*.md; do
  [[ -f "$src" ]] || continue

  basename_noext="$(basename "$src" .md)"
  parse_md "$src"

  name=$(yaml_val "name" "$FM")
  description=$(yaml_val "description" "$FM")
  tools_raw=$(yaml_val "tools" "$FM")

  if [[ -z "$name" ]]; then
    name="$basename_noext"
  fi

  if [[ -z "$description" ]]; then
    echo "  SKIP: $src — missing description field" >&2
    continue
  fi

  echo "Syncing agent: ${name}"

  # --- Copilot (.github/agents/*.agent.md) ---
  copilot_content="${GENERATED_MARKER}
---
name: ${name}
description: >
  ${description}
$([ -n "$tools_raw" ] && echo "tools: [${tools_raw}]")
---

${BODY}"

  write_file "${REPO_ROOT}/.github/agents/${basename_noext}.agent.md" "$copilot_content"

  # --- opencode (.opencode/agents/*.md) ---
  opencode_content="${GENERATED_MARKER}
---
name: ${name}
description: >
  ${description}
$([ -n "$tools_raw" ] && echo "tools: ${tools_raw}")
---

${BODY}"

  write_file "${REPO_ROOT}/.opencode/agents/${basename_noext}.md" "$opencode_content"

  # --- Claude Code (.claude/agents/*.md) ---
  claude_content="${GENERATED_MARKER}
---
name: ${name}
description: >
  ${description}
$([ -n "$tools_raw" ] && echo "tools: ${tools_raw}")
---

${BODY}"

  write_file "${REPO_ROOT}/.claude/agents/${basename_noext}.md" "$claude_content"

  # --- Codex (.codex/agents/*.toml) ---
  # Escape the body for TOML multiline string (triple quotes).
  # TOML triple-quoted strings handle most content; only \ needs escaping.
  toml_body="${BODY//\\/\\\\}"

  codex_content="${GENERATED_MARKER}
# Source: .agents/agents/${basename_noext}.md

[agent]
name = \"${name}\"
description = \"${description}\"
$([ -n "$tools_raw" ] && echo "# tools: ${tools_raw} — map to Codex equivalents if needed")

instructions = \"\"\"
${toml_body}
\"\"\""

  write_file "${REPO_ROOT}/.codex/agents/${basename_noext}.toml" "$codex_content"

  # --- Cursor (.cursor/agents/*.md) ---
  cursor_content="${GENERATED_MARKER}
---
name: ${name}
description: >
  ${description}
$([ -n "$tools_raw" ] && echo "tools: ${tools_raw}")
---

${BODY}"

  write_file "${REPO_ROOT}/.cursor/agents/${basename_noext}.md" "$cursor_content"

  count=$((count + 1))
done

echo ""
if $DRY_RUN; then
  echo "Dry run complete. ${count} agent(s) would be synced."
else
  echo "Done. ${count} agent(s) synced to 5 harness targets."
fi
