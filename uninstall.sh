#!/usr/bin/env bash
# uninstall.sh — Uninstaller for memory-keeper-hooks
# Reverses everything install.sh does, with confirmation prompts
# Safe to re-run — skips already-removed items

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
CLAUDE_JSON="$HOME/.claude.json"
SETTINGS_JSON="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

# Files installed by install.sh
SKILLS=(
  "$CLAUDE_DIR/skills/memory-keeper-session.md"
  "$CLAUDE_DIR/skills/memory-keeper-feature.md"
  "$CLAUDE_DIR/skills/memory-keeper-debug.md"
  "$CLAUDE_DIR/skills/memory-keeper-maintenance.md"
  "$CLAUDE_DIR/skills/memory-keeper-mixin.md"
)
AGENTS=(
  "$CLAUDE_DIR/agents/journal.md"
  "$CLAUDE_DIR/agents/examples/debug-investigator.md"
)
HOOKS=(
  "$CLAUDE_DIR/hooks/journal-trigger.sh"
  "$CLAUDE_DIR/hooks/subagent-journal-trigger.sh"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

DRY_RUN=false
REMOVE_MCP=false
REMOVE_DATA=false

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --dry-run       Show what would be removed without doing it"
  echo "  --remove-mcp    Also remove memory-keeper MCP server from ~/.claude.json"
  echo "  --remove-data   Also remove MCP data at ~/mcp-data/memory-keeper"
  echo "  --full          Equivalent to --remove-mcp --remove-data"
  echo "  -h, --help      Show this help"
  echo ""
  echo "By default, only hooks, skills, agents, and CLAUDE.md patch are removed."
  echo "MCP server config and data are preserved (they may be used by other tools)."
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --remove-mcp) REMOVE_MCP=true ;;
    --remove-data) REMOVE_DATA=true ;;
    --full)       REMOVE_MCP=true; REMOVE_DATA=true ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║    memory-keeper-hooks uninstaller       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

if $DRY_RUN; then
  echo -e "${YELLOW}  DRY RUN — no changes will be made${NC}"
  echo ""
fi

removed=0
skipped=0

do_rm() {
  local file="$1"
  if [ -f "$file" ]; then
    if $DRY_RUN; then
      echo -e "  ${YELLOW}would remove${NC} $file"
    else
      rm "$file"
      echo -e "  ${RED}✗${NC} removed $file"
    fi
    removed=$((removed + 1))
  else
    echo -e "  ${GREEN}✓${NC} already absent: $(basename "$file")"
    skipped=$((skipped + 1))
  fi
}

# ─────────────────────────────────────────────
# STEP 1 — Remove hooks from settings.json
# ─────────────────────────────────────────────
echo "── Step 1: Removing hooks from settings.json"

if [ -f "$SETTINGS_JSON" ]; then
  if $DRY_RUN; then
    echo -e "  ${YELLOW}would patch${NC} $SETTINGS_JSON (remove journal-trigger entries)"
  else
    cp "$SETTINGS_JSON" "$SETTINGS_JSON.pre-uninstall"

    python3 - "$SETTINGS_JSON" << 'PYEOF'
import json
import sys

settings_path = sys.argv[1]
with open(settings_path, "r") as f:
    data = json.load(f)

hooks = data.get("hooks", {})
changed = False

for event_type in list(hooks.keys()):
    entries = hooks[event_type]
    filtered = []
    for entry in entries:
        hook_list = entry.get("hooks", [])
        clean_hooks = [
            h for h in hook_list
            if not (
                h.get("command", "").endswith("journal-trigger.sh")
                or h.get("command", "").endswith("subagent-journal-trigger.sh")
            )
        ]
        if len(clean_hooks) < len(hook_list):
            changed = True
        if clean_hooks:
            entry["hooks"] = clean_hooks
            filtered.append(entry)

    if filtered:
        hooks[event_type] = filtered
    else:
        del hooks[event_type]
        changed = True

if changed:
    data["hooks"] = hooks
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("  \033[0;31m✗\033[0m journal hook entries removed from settings.json")
else:
    print("  \033[0;32m✓\033[0m no journal hooks found in settings.json")
PYEOF
  fi
else
  echo -e "  ${GREEN}✓${NC} settings.json not found — nothing to patch"
fi

echo ""

# ─────────────────────────────────────────────
# STEP 2 — Remove installed skills
# ─────────────────────────────────────────────
echo "── Step 2: Removing skills"

for skill in "${SKILLS[@]}"; do
  do_rm "$skill"
done

echo ""

# ─────────────────────────────────────────────
# STEP 3 — Remove sub-agent
# ─────────────────────────────────────────────
echo "── Step 3: Removing sub-agent"

for agent in "${AGENTS[@]}"; do
  do_rm "$agent"
done

# Clean up examples dir if empty
if [ -d "$CLAUDE_DIR/agents/examples" ] && [ -z "$(ls -A "$CLAUDE_DIR/agents/examples" 2>/dev/null)" ]; then
  if $DRY_RUN; then
    echo -e "  ${YELLOW}would remove${NC} empty directory agents/examples/"
  else
    rmdir "$CLAUDE_DIR/agents/examples"
    echo -e "  ${RED}✗${NC} removed empty directory agents/examples/"
  fi
fi

echo ""

# ─────────────────────────────────────────────
# STEP 4 — Remove hook scripts
# ─────────────────────────────────────────────
echo "── Step 4: Removing hook scripts"

for hook in "${HOOKS[@]}"; do
  do_rm "$hook"
done

echo ""

# ─────────────────────────────────────────────
# STEP 5 — Remove CLAUDE.md patch
# ─────────────────────────────────────────────
echo "── Step 5: Removing memory-keeper-workflow section from CLAUDE.md"

if [ -f "$CLAUDE_MD" ]; then
  START_MARKER="# --- memory-keeper-workflow START ---"
  END_MARKER="# --- memory-keeper-workflow END ---"

  if grep -q "$START_MARKER" "$CLAUDE_MD"; then
    if $DRY_RUN; then
      echo -e "  ${YELLOW}would remove${NC} block between START/END markers in CLAUDE.md"
    else
      cp "$CLAUDE_MD" "$CLAUDE_MD.pre-uninstall"
      # Remove the block including markers and surrounding blank lines
      python3 - "$CLAUDE_MD" "$START_MARKER" "$END_MARKER" << 'PYEOF'
import sys

filepath = sys.argv[1]
start_marker = sys.argv[2]
end_marker = sys.argv[3]

with open(filepath, "r") as f:
    lines = f.readlines()

result = []
inside_block = False
for line in lines:
    if start_marker in line:
        inside_block = True
        continue
    if end_marker in line:
        inside_block = False
        continue
    if not inside_block:
        result.append(line)

# Strip leading/trailing blank lines from result
while result and result[0].strip() == "":
    result.pop(0)
while result and result[-1].strip() == "":
    result.pop()

with open(filepath, "w") as f:
    f.writelines(result)
    f.write("\n")

print("  \033[0;31m✗\033[0m memory-keeper-workflow section removed from CLAUDE.md")
PYEOF
    fi
  else
    echo -e "  ${GREEN}✓${NC} no memory-keeper-workflow markers found in CLAUDE.md"
  fi
else
  echo -e "  ${GREEN}✓${NC} CLAUDE.md not found — nothing to patch"
fi

echo ""

# ─────────────────────────────────────────────
# STEP 6 (optional) — Remove MCP server config
# ─────────────────────────────────────────────
if $REMOVE_MCP; then
  echo "── Step 6: Removing memory-keeper MCP server from ~/.claude.json"

  if [ -f "$CLAUDE_JSON" ]; then
    if $DRY_RUN; then
      echo -e "  ${YELLOW}would remove${NC} memory-keeper entry from ~/.claude.json"
    else
      cp "$CLAUDE_JSON" "$CLAUDE_JSON.pre-uninstall"

      python3 - "$CLAUDE_JSON" << 'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path, "r") as f:
    data = json.load(f)

servers = data.get("mcpServers", {})
removed = [k for k in servers if k == "memory-keeper"]

for k in removed:
    del servers[k]

if removed:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"  \033[0;31m✗\033[0m removed {', '.join(removed)} from ~/.claude.json")
else:
    print("  \033[0;32m✓\033[0m no memory-keeper server found in ~/.claude.json")
PYEOF
    fi
  else
    echo -e "  ${GREEN}✓${NC} ~/.claude.json not found"
  fi

  echo ""
fi

# ─────────────────────────────────────────────
# STEP 7 (optional) — Remove MCP data
# ─────────────────────────────────────────────
if $REMOVE_DATA; then
  echo "── Step 7: Removing MCP data"

  MK_DATA_DIR="$HOME/mcp-data/memory-keeper"
  if [ -d "$MK_DATA_DIR" ]; then
    if $DRY_RUN; then
      DB_SIZE=$(du -sh "$MK_DATA_DIR" | cut -f1)
      echo -e "  ${YELLOW}would remove${NC} $MK_DATA_DIR ($DB_SIZE)"
    else
      DB_SIZE=$(du -sh "$MK_DATA_DIR" | cut -f1)
      echo -e "  ${RED}⚠ WARNING: This will permanently delete all memory-keeper data ($DB_SIZE)${NC}"
      read -p "  Type 'yes' to confirm: " confirm
      if [ "$confirm" = "yes" ]; then
        rm -rf "$MK_DATA_DIR"
        echo -e "  ${RED}✗${NC} removed $MK_DATA_DIR"
        # Remove parent if empty
        if [ -d "$HOME/mcp-data" ] && [ -z "$(ls -A "$HOME/mcp-data" 2>/dev/null)" ]; then
          rmdir "$HOME/mcp-data"
          echo -e "  ${RED}✗${NC} removed empty ~/mcp-data/"
        fi
      else
        echo "  Skipped — data preserved"
      fi
    fi
  else
    echo -e "  ${GREEN}✓${NC} $MK_DATA_DIR not found"
  fi

  echo ""
fi

# ─────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────
echo "╔══════════════════════════════════════════╗"
if $DRY_RUN; then
echo "║        Dry run complete                  ║"
else
echo "║        Uninstall complete                ║"
fi
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Removed: $removed items"
echo "  Already absent: $skipped items"
echo ""

if ! $DRY_RUN; then
  echo "Backups created:"
  [ -f "$SETTINGS_JSON.pre-uninstall" ] && echo "  $SETTINGS_JSON.pre-uninstall"
  [ -f "$CLAUDE_MD.pre-uninstall" ] && echo "  $CLAUDE_MD.pre-uninstall"
  $REMOVE_MCP && [ -f "$CLAUDE_JSON.pre-uninstall" ] && echo "  $CLAUDE_JSON.pre-uninstall"
  echo ""
  echo "→ Restart Claude Code to apply changes"
fi
echo ""
