#!/usr/bin/env bash
# merge.sh — Merges memory-keeper-workflow patch into ~/.claude/CLAUDE.md
# Safe to run multiple times — detects existing patch and skips or updates

set -euo pipefail

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
PATCH_FILE="$(dirname "$0")/patch.md"
MARKER_START="# --- memory-keeper-workflow START ---"
MARKER_END="# --- memory-keeper-workflow END ---"

echo "→ Checking CLAUDE.md at $CLAUDE_MD"

# Create CLAUDE.md if it doesn't exist
if [ ! -f "$CLAUDE_MD" ]; then
  echo "  CLAUDE.md not found — creating empty file"
  mkdir -p "$(dirname "$CLAUDE_MD")"
  touch "$CLAUDE_MD"
fi

# Check if patch already present
if grep -q "memory-keeper-workflow START" "$CLAUDE_MD" 2>/dev/null; then
  echo "  Patch already present — checking if update needed"

  # Extract current patch content (between markers)
  current=$(sed -n "/$MARKER_START/,/$MARKER_END/p" "$CLAUDE_MD")
  new=$(cat "$PATCH_FILE")

  if [ "$current" = "$new" ]; then
    echo "  Patch is up to date — nothing to do"
    exit 0
  fi

  echo "  Patch outdated — updating"

  # Remove existing patch block
  tmp=$(mktemp)
  sed "/$MARKER_START/,/$MARKER_END/d" "$CLAUDE_MD" > "$tmp"

  # Remove trailing blank lines before appending
  sed -i '' -e 's/[[:space:]]*$//' "$tmp"

  # Append updated patch
  echo "" >> "$tmp"
  cat "$PATCH_FILE" >> "$tmp"
  mv "$tmp" "$CLAUDE_MD"

  echo "  ✓ Patch updated in $CLAUDE_MD"
else
  echo "  Patch not found — appending to $CLAUDE_MD"

  # Add blank line separator if file is non-empty
  if [ -s "$CLAUDE_MD" ]; then
    echo "" >> "$CLAUDE_MD"
  fi

  cat "$PATCH_FILE" >> "$CLAUDE_MD"
  echo "  ✓ Patch appended to $CLAUDE_MD"
fi
