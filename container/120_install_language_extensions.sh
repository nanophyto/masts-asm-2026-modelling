#!/usr/bin/env bash
set -euo pipefail

# Google's Code OSS startup task 110 launches the IDE. The documented 120
# startup stage installs user extensions into the persistent editor profile.
# Bundled VSIX files avoid marketplace access during workshop sessions.
username=user
home_dir=/home/user
id "$username" >/dev/null
runuser -u "$username" -- env HOME="$home_dir" \
    /opt/workshop/python/bin/python /opt/workshop/ensure_language_extensions.py ensure \
    /opt/code-oss/bin/codeoss-cloudworkstations /opt/workshop/vsix
