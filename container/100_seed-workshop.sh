#!/usr/bin/env bash
set -euo pipefail

# Workstations creates this user and mounts /home at runtime.
username=user
home_dir=/home/user
workspace="$home_dir/masts-asm-2026-modelling"

id "$username" >/dev/null

# Seed editable examples once per participant; preserve subsequent edits.
if [[ ! -f "$workspace/README.md" ]]; then
    runuser -u "$username" -- mkdir -p "$workspace"
    runuser -u "$username" -- cp -R /opt/workshop/source/. "$workspace/"
fi

# Default editor settings, only on the first run.
settings_dir="$workspace/.vscode"
runuser -u "$username" -- mkdir -p "$settings_dir"
if [[ ! -f "$settings_dir/settings.json" ]]; then
    sed "s|__WORKSPACE__|$workspace|g" /opt/workshop/workspace-settings.json \
        | runuser -u "$username" -- tee "$settings_dir/settings.json" >/dev/null
fi
