#!/usr/bin/env python3
# ~/.claude/hooks/patch-settings.py
#
# Script d'installation : ajoute les hooks journal au settings.json global.
# À lancer une fois : python3 ~/.claude/hooks/patch-settings.py
#
# Idempotent — vérifie si les hooks sont déjà présents avant d'ajouter.

import json
import os
import shutil
from datetime import datetime

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
    # Lire le settings.json existant
    if os.path.exists(SETTINGS_PATH):
        with open(SETTINGS_PATH, "r") as f:
            settings = json.load(f)
    else:
        settings = {}
        print(f"[info] {SETTINGS_PATH} n'existe pas, création.")

    # Backup
    backup_path = f"{SETTINGS_PATH}.backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    if os.path.exists(SETTINGS_PATH):
        shutil.copy2(SETTINGS_PATH, backup_path)
        print(f"[backup] {backup_path}")

    # S'assurer que hooks existe
    if "hooks" not in settings:
        settings["hooks"] = {}

    # Ajouter chaque hook si pas déjà présent
    for event, hook_config in HOOKS_TO_ADD.items():
        if event not in settings["hooks"]:
            settings["hooks"][event] = hook_config
            print(f"[added] hook {event}")
        else:
            # Vérifier si le script est déjà configuré
            existing_commands = [
                h.get("command", "")
                for matcher in settings["hooks"][event]
                for h in matcher.get("hooks", [])
                if h.get("type") == "command"
            ]
            if HOOK_SCRIPT not in existing_commands:
                settings["hooks"][event].extend(hook_config)
                print(f"[added] hook {event} (merged avec existant)")
            else:
                print(f"[skip] hook {event} déjà configuré")

    # Écrire
    with open(SETTINGS_PATH, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"[done] {SETTINGS_PATH} mis à jour.")
    print(f"\nProchaine étape : chmod +x {HOOK_SCRIPT}")

if __name__ == "__main__":
    main()
