#!/usr/bin/env bash
set -euo pipefail

# Workstations creates this user and mounts /home at runtime.
username=user
home_dir=/home/user
workspace="$home_dir/masts-asm-2026-modelling"

id "$username" >/dev/null

# A new persistent home volume may be owned by root. Give the workstation
# account ownership of the home directory while preserving existing files.
mkdir -p "$home_dir"
chown "$(id -u "$username"):$(id -g "$username")" "$home_dir"

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

# Google Code OSS reads machine-wide defaults from this persistent-home path.
# Install missing defaults for fresh and existing volumes before IDE startup,
# leaving any already customised setting intact.
editor_root="$home_dir/.codeoss-cloudworkstations"
editor_data="$editor_root/data"
machine_dir="$editor_data/Machine"
mkdir -p "$machine_dir"
chown "$(id -u "$username"):$(id -g "$username")" "$editor_root" "$editor_data" "$machine_dir"
runuser -u "$username" -- /opt/workshop/python/bin/python \
    /opt/workshop/configure_editor.py merge-defaults \
    /opt/workshop/machine-settings.json "$machine_dir/settings.json"

# Remove optional Google AI extensions retained in a participant's persistent
# editor profile from earlier image versions. The Julia extension is preserved.
if [[ -d "$editor_root/extensions" ]]; then
    runuser -u "$username" -- /opt/workshop/python/bin/python \
        /opt/workshop/configure_editor.py remove-google-ai "$editor_root/extensions"
fi
