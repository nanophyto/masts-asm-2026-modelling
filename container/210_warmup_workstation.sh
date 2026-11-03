#!/usr/bin/env bash
set -euo pipefail

# Start this optional task during the operator's early workstation start.
# It prepares persistent per-user editor caches and runs a annual science
# check in a private cache directory, without blocking Code OSS startup.
if [[ "${MASTS_WARMUP_ON_START:-0}" != "1" ]]; then
    exit 0
fi
id user >/dev/null
if ! runuser -u user -- env HOME=/home/user \
    /opt/workshop/python/bin/python /opt/workshop/warmup_workstation.py launch; then
    echo "Warning: MASTS warm-up could not start; Code OSS remains available" >&2
fi
