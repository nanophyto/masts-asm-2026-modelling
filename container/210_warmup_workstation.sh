#!/usr/bin/env bash
set -euo pipefail

# Prepare persistent per-user editor caches and a short science check.
# Runs in the background without blocking Code OSS startup.
if [[ "${MASTS_WARMUP_ON_START:-1}" != "1" ]]; then
    exit 0
fi
id user >/dev/null
if ! runuser -u user -- env HOME=/home/user \
    /opt/workshop/python/bin/python /opt/workshop/warmup_workstation.py launch; then
    echo "Warning: MASTS warm-up could not start; Code OSS remains available" >&2
fi
