#!/usr/bin/env bash
set -euo pipefail

id user >/dev/null
runuser -u user -- env HOME=/home/user \
    /opt/workshop/python/bin/python /opt/workshop/ensure_language_extensions.py \
    ensure-abil /opt/code-oss/bin/codeoss-cloudworkstations /opt/workshop/vsix
