#!/usr/bin/env bash
# install.sh — Installer for memory-keeper-hooks
# Extension du plugin memory-keeper-workflow : ajoute hooks + sub-agent journal
# Idempotent — peut être relancé sans risque

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
AGENTS_DIR="$CLAUDE_DIR/agents"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SKILLS_DIR="$CLAUDE_DIR/skills"
MK_DATA_DIR="$HOME/mcp-data/memory-keeper"
MK_PACKAGE="mcp-memory-keeper"
CLAUDE_JSON="$HOME/.claude.json"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     memory-keeper-hooks installer        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────
# STEP 1 — Check prerequisites
# ─────────────────────────────────────────────
echo "── Step 1: Checking prerequisites"

if ! command -v node &>/dev/null; then
  echo "  ✗ Node.js not found — please install Node.js first"
  echo "    brew install node"
  exit 1
fi
echo "  ✓ Node.js $(node --version)"

if ! command -v npx &>/dev/null; then
  echo "  ✗ npx not found — please install Node.js (includes npx)"
  exit 1
fi
echo "  ✓ npx available"

if ! command -v python3 &>/dev/null; then
  echo "  ✗ python3 not found — required to patch ~/.claude.json"
  echo "    brew install python3"
  exit 1
fi
echo "  ✓ python3 available"

if ! command -v jq &>/dev/null; then
  echo "  ✗ jq not found — required for hook scripts"
  echo "    brew install jq"
  exit 1
fi
echo "  ✓ jq available"

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "  ✗ ~/.claude directory not found — is Claude Code installed?"
  exit 1
fi
echo "  ✓ ~/.claude directory exists"

echo ""

# ─────────────────────────────────────────────
# STEP 2 — Check memory-keeper installation
# ─────────────────────────────────────────────
echo "── Step 2: Checking memory-keeper"

MK_RUNNING=false
MK_DB_OK=false
MK_CONFIGURED=false

if pgrep -f "mcp-memory-keeper" &>/dev/null; then
  MK_RUNNING=true
  echo "  ✓ memory-keeper process is running"
else
  echo "  ✗ memory-keeper process not detected"
fi

if [ -f "$MK_DATA_DIR/context.db" ]; then
  MK_DB_OK=true
  DB_SIZE=$(du -h "$MK_DATA_DIR/context.db" | cut -f1)
  echo "  ✓ Database found at $MK_DATA_DIR/context.db ($DB_SIZE)"
else
  echo "  ✗ Database not found at $MK_DATA_DIR/context.db"
fi

if [ -f "$CLAUDE_JSON" ] && python3 -c "
import json, sys
data = json.load(open('$CLAUDE_JSON'))
servers = data.get('mcpServers', {})
found = any('memory-keeper' in k or 'memory_keeper' in k for k in servers)
sys.exit(0 if found else 1)
" 2>/dev/null; then
  MK_CONFIGURED=true
  echo "  ✓ memory-keeper found in user scope config (~/.claude.json)"
else
  echo "  ✗ memory-keeper not found in ~/.claude.json (user scope)"
fi

echo ""

# ─────────────────────────────────────────────
# STEP 3 — Install or repair memory-keeper
# ─────────────────────────────────────────────
echo "── Step 3: memory-keeper setup"

if $MK_RUNNING && $MK_DB_OK && $MK_CONFIGURED; then
  echo "  ✓ memory-keeper is fully operational — nothing to install"
else
  echo "  Issues detected — attempting to resolve"
  echo ""

  if [ ! -d "$MK_DATA_DIR" ]; then
    echo "  Creating data directory at $MK_DATA_DIR"
    mkdir -p "$MK_DATA_DIR"
  fi

  echo "  Installing $MK_PACKAGE globally via npm"
  if npm install -g "$MK_PACKAGE"; then
    echo "  ✓ $MK_PACKAGE installed globally"
  else
    echo "  ✗ npm install failed — check your Node.js setup"
    exit 1
  fi

  if ! $MK_CONFIGURED; then
    echo ""
    echo "  Registering memory-keeper in ~/.claude.json (user scope)"

    python3 << PYEOF
import json
import os

claude_json_path = os.path.expanduser("~/.claude.json")
mk_data_dir = os.path.expanduser("~/mcp-data/memory-keeper")

if os.path.exists(claude_json_path):
    with open(claude_json_path, "r") as f:
        data = json.load(f)
else:
    data = {}

if "mcpServers" not in data:
    data["mcpServers"] = {}

data["mcpServers"]["memory-keeper"] = {
    "command": "npx",
    "args": ["mcp-memory-keeper"],
    "env": {
        "DATA_DIR": mk_data_dir,
        "TOOL_PROFILE": "full",
        "MCP_MAX_TOKENS": "8000",
        "MCP_TOKEN_SAFETY_BUFFER": "0.8",
        "MCP_MIN_ITEMS": "3",
        "MCP_MAX_ITEMS": "50",
        "MEMORY_KEEPER_AUTO_UPDATE": "1"
    }
}

with open(claude_json_path, "w") as f:
    json.dump(data, f, indent=2)

print("  ✓ memory-keeper written to ~/.claude.json")
PYEOF

    echo ""
    echo "  ✓ Configuration complete"
    echo "  ⚠ Restart Claude Code to activate memory-keeper"
  fi
fi

echo ""

# ─────────────────────────────────────────────
# STEP 4 — Install skills
# ─────────────────────────────────────────────
echo "── Step 4: Installing skills"

mkdir -p "$SKILLS_DIR"

for skill in "$SCRIPT_DIR/skills/"*.md; do
  filename=$(basename "$skill")
  dest="$SKILLS_DIR/$filename"

  if [ -f "$dest" ]; then
    if diff -q "$skill" "$dest" &>/dev/null; then
      echo "  ✓ $filename — already up to date"
    else
      cp "$skill" "$dest"
      echo "  ↑ $filename — updated"
    fi
  else
    cp "$skill" "$dest"
    echo "  + $filename — installed"
  fi
done

echo ""

# ─────────────────────────────────────────────
# STEP 5 — Install sub-agent
# ─────────────────────────────────────────────
echo "── Step 5: Installing sub-agent"

mkdir -p "$AGENTS_DIR"

AGENT_SRC="$SCRIPT_DIR/agents/journal.md"
AGENT_DEST="$AGENTS_DIR/journal.md"

if [ -f "$AGENT_DEST" ]; then
  if diff -q "$AGENT_SRC" "$AGENT_DEST" &>/dev/null; then
    echo "  ✓ journal.md — already up to date"
  else
    cp "$AGENT_SRC" "$AGENT_DEST"
    echo "  ↑ journal.md — updated"
  fi
else
  cp "$AGENT_SRC" "$AGENT_DEST"
  echo "  + journal.md — installed"
fi

echo ""

# ─────────────────────────────────────────────
# STEP 6 — Install hook script
# ─────────────────────────────────────────────
echo "── Step 6: Installing hook script"

mkdir -p "$HOOKS_DIR"

HOOK_SRC="$SCRIPT_DIR/hooks/journal-trigger.sh"
HOOK_DEST="$HOOKS_DIR/journal-trigger.sh"

if [ -f "$HOOK_DEST" ]; then
  if diff -q "$HOOK_SRC" "$HOOK_DEST" &>/dev/null; then
    echo "  ✓ journal-trigger.sh — already up to date"
  else
    cp "$HOOK_SRC" "$HOOK_DEST"
    echo "  ↑ journal-trigger.sh — updated"
  fi
else
  cp "$HOOK_SRC" "$HOOK_DEST"
  echo "  + journal-trigger.sh — installed"
fi

chmod +x "$HOOK_DEST"
echo "  ✓ journal-trigger.sh — executable"

echo ""

# ─────────────────────────────────────────────
# STEP 7 — Patch settings.json
# ─────────────────────────────────────────────
echo "── Step 7: Patching ~/.claude/settings.json"

python3 "$SCRIPT_DIR/hooks/patch-settings.py"

echo ""

# ─────────────────────────────────────────────
# STEP 8 — Merge CLAUDE.md patch
# ─────────────────────────────────────────────
echo "── Step 8: Updating ~/.claude/CLAUDE.md"

chmod +x "$SCRIPT_DIR/claude-md-patch/merge.sh"
"$SCRIPT_DIR/claude-md-patch/merge.sh"

echo ""

# ─────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────
echo "╔══════════════════════════════════════════╗"
echo "║           Installation complete          ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Installed skills:"
echo "  ~/.claude/skills/memory-keeper-session.md"
echo "  ~/.claude/skills/memory-keeper-feature.md"
echo "  ~/.claude/skills/memory-keeper-debug.md"
echo "  ~/.claude/skills/memory-keeper-maintenance.md"
echo ""
echo "Installed sub-agent:"
echo "  ~/.claude/agents/journal.md"
echo ""
echo "Installed hook:"
echo "  ~/.claude/hooks/journal-trigger.sh"
echo ""
echo "CLAUDE.md updated: ~/.claude/CLAUDE.md"
echo ""
echo "→ Restart Claude Code to activate"
echo "→ Verify: claude agents | grep journal"
echo "→ Verify: cat ~/.claude/settings.json | jq '.hooks'"
echo ""
