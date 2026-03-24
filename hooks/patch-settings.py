import json
import os
import shutil
from datetime import datetime

# Installation script: adds journal hooks to the global settings.json.
# Run once: python3 ~/.claude/hooks/patch-settings.py
#
# Idempotent — checks if hooks are already present before adding.

SETTINGS_PATH = os.path.expanduser("~/.claude/settings.json")
HOOK_SCRIPT   = os.path.expanduser("~/.claude/hooks/journal-trigger.sh")

HOOKS_TO_ADD = {
    "Stop": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": HOOK_SCRIPT,
                    "async": True,
                    "timeout": 120
                }
            ]
        }
    ],
    "PreCompact": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": HOOK_SCRIPT,
                    "async": True,
                    "timeout": 120
                }
            ]
        }
    ]
}

def main():
    # Read existing settings.json
    if os.path.exists(SETTINGS_PATH):
        with open(SETTINGS_PATH, "r") as f:
            settings = json.load(f)
    else:
        settings = {}
        print(f"[info] {SETTINGS_PATH} does not exist, creating.")

    backup_path = f"{SETTINGS_PATH}.backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    if os.path.exists(SETTINGS_PATH):
        shutil.copy2(SETTINGS_PATH, backup_path)
        print(f"[backup] {backup_path}")

    # Ensure hooks key exists
    if "hooks" not in settings:
        settings["hooks"] = {}

    # Add each hook if not already present
    for event, hook_config in HOOKS_TO_ADD.items():
        if event not in settings["hooks"]:
            settings["hooks"][event] = hook_config
            print(f"[added] hook {event}")
        else:
            # Check if the script is already configured
            existing_commands = [
                h.get("command", "")
                for matcher in settings["hooks"][event]
                for h in matcher.get("hooks", [])
                if h.get("type") == "command"
            ]
            if HOOK_SCRIPT not in existing_commands:
                settings["hooks"][event].extend(hook_config)
                print(f"[added] hook {event} (merged with existing)")
            else:
                print(f"[skip] hook {event} already configured")

    # Write
    with open(SETTINGS_PATH, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"[done] {SETTINGS_PATH} updated.")
    print(f"\nNext step: chmod +x {HOOK_SCRIPT}")

if __name__ == "__main__":
    main()
