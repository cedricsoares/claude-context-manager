#!/usr/bin/env bash
# ~/.claude/hooks/journal-trigger.sh
#
# Déclencheur du sub-agent journalisation memory-keeper.
# Utilisé par les hooks Stop et PreCompact dans settings.json.
#
# Reçoit le payload JSON de Claude Code via stdin.
# Détecte si la session mérite une journalisation et invoque le sub-agent journal.

set -euo pipefail

# --- Résolution robuste du binaire claude ---
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
  exit 0  # claude introuvable — sortie silencieuse
fi

# --- Lire le payload JSON ---
INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
CWD=$(echo "$INPUT"        | jq -r '.cwd // ""')
TRIGGER=$(echo "$INPUT"    | jq -r '.trigger // ""')          # pour PreCompact
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')  # pour Stop

# --- Garder de sauvegarder si PreCompact est deja actif (eviter les boucles) ---
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# --- Cas PreCompact : toujours déclencher ---
if [ "$HOOK_EVENT" = "PreCompact" ]; then
  "$CLAUDE_BIN" -p "Use the journal agent to journalise this session.
trigger=precompact
transcript_path=$TRANSCRIPT
cwd=$CWD
context=PreCompact imminent — sauvegarde le contexte avant perte." \
    --dangerously-skip-permissions \
    2>/dev/null || true
  exit 0
fi

# --- Cas Stop : détecter si un événement significatif s'est produit ---
if [ "$HOOK_EVENT" = "Stop" ]; then

  # Pas de transcript = impossible de décider
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
  fi

  # Extraire les outils utilisés dans les derniers échanges
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

  # Définir les outils déclencheurs
  WRITE_EDIT_PATTERN="Write|Edit|MultiEdit|NotebookEdit"
  BASH_SIGNIFICANT_PATTERN="git commit|git push|terraform apply|terraform plan|dbt run|dbt test|dbt build|prefect|kubectl apply|gcloud|npm run|pytest|go test"

  SHOULD_TRIGGER=false
  DETECTED=""

  # Vérifier Write/Edit
  if echo "$LAST_TOOLS" | grep -qE "$WRITE_EDIT_PATTERN"; then
    SHOULD_TRIGGER=true
    DETECTED="write_edit"
  fi

  # Vérifier les commandes Bash significatives
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

  # Rien de significatif détecté → ne pas déclencher
  if [ "$SHOULD_TRIGGER" = "false" ]; then
    exit 0
  fi

  # Invoquer le sub-agent journal
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

# Autre événement non géré
exit 0
