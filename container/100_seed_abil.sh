#!/usr/bin/env bash
set -euo pipefail

username=user
home_dir=/home/user
workspace="$home_dir/masts-asm-2026-modelling"

id "$username" >/dev/null
mkdir -p "$home_dir"
chown "$(id -u "$username"):$(id -g "$username")" "$home_dir"

# Copy only missing workshop materials, preserving files edited by users.
runuser -u "$username" -- mkdir -p "$workspace"
runuser -u "$username" -- cp -R --no-clobber --preserve=mode,timestamps \
    /opt/workshop/source/. "$workspace/"

# Keep editor defaults suitable for both a root workspace and one opened
# directly at workshop/02_Abil by a deep link from the landing page.
for settings_dir in "$workspace/.vscode" "$workspace/workshop/02_Abil/.vscode"; do
    runuser -u "$username" -- mkdir -p "$settings_dir"
    if [[ ! -f "$settings_dir/settings.json" ]]; then
        sed 's|__WORKSPACE__|'"$workspace"'|g' \
            /opt/workshop/workspace-settings.json | \
            runuser -u "$username" -- tee "$settings_dir/settings.json" >/dev/null
    fi
done

# Cloud Code OSS stores machine settings and extensions on the persistent home.
editor_root="$home_dir/.codeoss-cloudworkstations"
editor_data="$editor_root/data"
machine_dir="$editor_data/Machine"
mkdir -p "$machine_dir"
chown "$(id -u "$username"):$(id -g "$username")" \
    "$editor_root" "$editor_data" "$machine_dir"
runuser -u "$username" -- /opt/workshop/python/bin/python \
    /opt/workshop/configure_editor.py merge-defaults \
    /opt/workshop/machine-settings.json "$machine_dir/settings.json"

if [[ -d "$editor_root/extensions" ]]; then
    runuser -u "$username" -- /opt/workshop/python/bin/python \
        /opt/workshop/configure_editor.py remove-google-ai "$editor_root/extensions"
fi
