#!/usr/bin/env bash
# ~/.claude/hooks/subagent-journal-trigger.sh
#
# Trigger for the memory-keeper journaling sub-agent on SubagentStop events.
# Captures work done by sub-agents (custom or third-party) and invokes the
# journal agent to persist significant findings in memory-keeper.
#
# This is the universal safety net: it covers ALL agents, including those
# that do not have the memory-keeper-mixin skill loaded.

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

HOOK_EVENT=$(echo "$INPUT"    | jq -r '.hook_event_name // "unknown"')
AGENT_TYPE=$(echo "$INPUT"    | jq -r '.agent_type // "unknown"')
AGENT_TRANSCRIPT=$(echo "$INPUT" | jq -r '.agent_transcript_path // ""')
LAST_MSG=$(echo "$INPUT"      | jq -r '.last_assistant_message // ""')
CWD=$(echo "$INPUT"           | jq -r '.cwd // ""')
TRANSCRIPT=$(echo "$INPUT"    | jq -r '.transcript_path // ""')
STOP_ACTIVE=$(echo "$INPUT"   | jq -r '.stop_hook_active // false')

# --- Only handle SubagentStop ---
if [ "$HOOK_EVENT" != "SubagentStop" ]; then
  exit 0
fi

# --- Anti-loop protection ---
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# --- Skip read-only agents (no significant work to journal) ---
if echo "$AGENT_TYPE" | grep -qE "^(Explore|Plan|claude-code-guide)$"; then
  exit 0
fi

# --- Skip if no sub-agent transcript available ---
if [ -z "$AGENT_TRANSCRIPT" ] || [ ! -f "$AGENT_TRANSCRIPT" ]; then
  exit 0
fi

# --- Extract tools used by the sub-agent ---
AGENT_TOOLS=$(tail -n 200 "$AGENT_TRANSCRIPT" | python3 -c "
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

# --- Detect significant work ---
WRITE_EDIT_PATTERN="Write|Edit|MultiEdit|NotebookEdit"
BASH_SIGNIFICANT_PATTERN="git commit|git push|terraform apply|terraform plan|dbt run|dbt test|dbt build|prefect|kubectl apply|gcloud|npm run|pytest|go test"

SHOULD_TRIGGER=false
DETECTED=""

# Check for Write/Edit tools
if echo "$AGENT_TOOLS" | grep -qE "$WRITE_EDIT_PATTERN"; then
  SHOULD_TRIGGER=true
  DETECTED="write_edit"
fi

# Check for significant Bash commands
if [ "$SHOULD_TRIGGER" = "false" ]; then
  AGENT_BASH_COMMANDS=$(tail -n 200 "$AGENT_TRANSCRIPT" | python3 -c "
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

  if echo "$AGENT_BASH_COMMANDS" | grep -qE "$BASH_SIGNIFICANT_PATTERN"; then
    SHOULD_TRIGGER=true
    DETECTED="bash_significant"
  fi
fi

# --- Detect if the sub-agent already journaled (self-journaled) ---
SELF_JOURNALED=false
if echo "$AGENT_TOOLS" | grep -qE "mcp__memory-keeper__context_save|mcp__memory-keeper__context_batch_save"; then
  SELF_JOURNALED=true
fi

# --- Decide whether to trigger ---
# Trigger if: significant work detected OR agent did NOT self-journal
if [ "$SHOULD_TRIGGER" = "false" ] && [ "$SELF_JOURNALED" = "true" ]; then
  # Agent self-journaled and did nothing significant beyond that — skip
  exit 0
fi

if [ "$SHOULD_TRIGGER" = "false" ] && [ "$SELF_JOURNALED" = "false" ]; then
  # No significant work AND no self-journaling — nothing to capture
  exit 0
fi

# --- Truncate last_assistant_message to 2000 chars ---
LAST_MSG_TRUNCATED=$(echo "$LAST_MSG" | head -c 2000)

# --- Invoke the journal sub-agent ---
"$CLAUDE_BIN" -p "Use the journal agent to journalise this sub-agent's work.
trigger=subagent_stop
agent_type=$AGENT_TYPE
agent_transcript_path=$AGENT_TRANSCRIPT
last_assistant_message=$LAST_MSG_TRUNCATED
self_journaled=$SELF_JOURNALED
detected_event=$DETECTED
transcript_path=$TRANSCRIPT
cwd=$CWD" \
  --dangerously-skip-permissions \
  2>/dev/null || true

exit 0
