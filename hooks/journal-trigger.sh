#!/usr/bin/env bash
# ~/.claude/hooks/journal-trigger.sh
#
# Trigger for the memory-keeper journaling sub-agent.
# Used by the Stop and PreCompact hooks in settings.json.
#
# Receives the JSON payload from Claude Code via stdin.
# Detects whether the session warrants journaling and invokes the journal sub-agent.

set -euo pipefail

# --- Robust resolution of the claude binary ---
CLAUDE_BIN=""
for candidate in \
    "$HOME/.local/bin/claude" \
    "/usr/local/bin/claude" \
    "/opt/homebrew/bin/claude"; do
  if [ -x "$candidate" ]; then
    CLAUDE_BIN="$candidate"
    break
  fi
done
if [ -z "$CLAUDE_BIN" ]; then
  CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
fi
if [ -z "$CLAUDE_BIN" ]; then
  exit 0  # claude not found — exit silently
fi

# --- Read the JSON payload ---
INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
CWD=$(echo "$INPUT"        | jq -r '.cwd // ""')
TRIGGER=$(echo "$INPUT"    | jq -r '.trigger // ""')          # for PreCompact
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')  # for Stop

# --- Skip save if PreCompact is already active (avoid loops) ---
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# --- Case PreCompact: always trigger ---
if [ "$HOOK_EVENT" = "PreCompact" ]; then
  "$CLAUDE_BIN" -p "Use the journal agent to journalise this session.
trigger=precompact
transcript_path=$TRANSCRIPT
cwd=$CWD
context=PreCompact imminent — save context before loss." \
    --dangerously-skip-permissions \
    2>/dev/null || true
  exit 0
fi

# --- Case Stop: detect whether a significant event occurred ---
if [ "$HOOK_EVENT" = "Stop" ]; then

  # No transcript = cannot decide
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
  fi

  # Extract tools used in the latest exchanges
  LAST_TOOLS=$(tail -n 100 "$TRANSCRIPT" | python3 -c "
import sys, json
tools = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        content = obj.get('message', {}).get('content', [])
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'tool_use':
                    tools.append(block.get('name', ''))
    except:
        pass
print(','.join(tools))
" 2>/dev/null)

  # Define trigger tools
  WRITE_EDIT_PATTERN="Write|Edit|MultiEdit|NotebookEdit"
  BASH_SIGNIFICANT_PATTERN="git commit|git push|terraform apply|terraform plan|dbt run|dbt test|dbt build|prefect|kubectl apply|gcloud|npm run|pytest|go test"

  SHOULD_TRIGGER=false
  DETECTED=""

  # Check for Write/Edit
  if echo "$LAST_TOOLS" | grep -qE "$WRITE_EDIT_PATTERN"; then
    SHOULD_TRIGGER=true
    DETECTED="write_edit"
  fi

  # Check for significant Bash commands
  if [ "$SHOULD_TRIGGER" = "false" ]; then
    LAST_BASH_COMMANDS=$(tail -n 100 "$TRANSCRIPT" | python3 -c "
import sys, json
cmds = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        content = obj.get('message', {}).get('content', [])
        if isinstance(content, list):
            for block in content:
                if (isinstance(block, dict)
                    and block.get('type') == 'tool_use'
                    and block.get('name') == 'Bash'):
                    cmd = block.get('input', {}).get('command', '')
                    if cmd:
                        cmds.append(cmd[:200])
    except:
        pass
print('\n'.join(cmds))
" 2>/dev/null)

    if echo "$LAST_BASH_COMMANDS" | grep -qE "$BASH_SIGNIFICANT_PATTERN"; then
      SHOULD_TRIGGER=true
      DETECTED="bash_significant"
    fi
  fi

  # Nothing significant detected — do not trigger
  if [ "$SHOULD_TRIGGER" = "false" ]; then
    exit 0
  fi

  # Invoke the journal sub-agent
  "$CLAUDE_BIN" -p "Use the journal agent to journalise this session.
trigger=stop_event
detected_tools=$LAST_TOOLS
detected_event=$DETECTED
transcript_path=$TRANSCRIPT
cwd=$CWD" \
    --dangerously-skip-permissions \
    2>/dev/null || true
  exit 0
fi

# Other unhandled event
exit 0
