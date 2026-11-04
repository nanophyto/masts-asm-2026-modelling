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

# Seed missing workshop files on each start, preserving participant edits.
# Preserved timestamps allow reuse of Julia caches at this absolute path.
runuser -u "$username" -- mkdir -p "$workspace"
runuser -u "$username" -- cp -R --no-clobber --preserve=mode,timestamps \
    /opt/workshop/source/. "$workspace/"

# Keep the instructor-maintained Julia package implementation in sync with
# the image when reusing a participant home from an earlier workshop version.
# Exercise scripts are seeded above only when missing, preserving user edits.
for source_file in oceanbiome/src/MASTSWorkshop.jl \
                   oceanbiome/ext/MASTSWorkshopMakieExt.jl; do
    runuser -u "$username" -- cp --preserve=mode,timestamps \
        "/opt/workshop/source/$source_file" "$workspace/$source_file"
done

# Retire the original mixing exercise when it is an unedited seeded copy.
# A participant's modified script remains intact.
old_mixing="$workspace/workshop/01_OceanBioME/04_mixing.jl"
old_mixing_sha="84231069aaaa79be8baececd1a72c292a259f1f6b4aa6c80ee9d8be582d7f998"
if [[ -f "$old_mixing" ]] && \
   [[ "$(sha256sum "$old_mixing" | cut -d ' ' -f1)" == "$old_mixing_sha" ]]; then
    runuser -u "$username" -- rm "$old_mixing"
fi

# Default editor settings, only on the first run.
for settings_dir in "$workspace/.vscode" "$workspace/workshop/.vscode"; do
    runuser -u "$username" -- mkdir -p "$settings_dir"
    if [[ ! -f "$settings_dir/settings.json" ]]; then
        sed "s|__WORKSPACE__|$workspace|g" /opt/workshop/workspace-settings.json \
            | runuser -u "$username" -- tee "$settings_dir/settings.json" >/dev/null
    fi
    # Preserve previous user settings and migrate the older Julia executable.
    runuser -u "$username" -- /opt/workshop/python/bin/python \
        /opt/workshop/configure_editor.py migrate-workspace-julia "$settings_dir/settings.json"
done

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
