#!/usr/bin/env bash
set -euo pipefail

image="${1:-masts-asm-2026-modelling:local}"
if ! command -v docker >/dev/null 2>&1; then
    echo 'Docker is required for this benchmark.' >&2
    exit 1
fi

# Two independently started Julia processes, from the same tested image.
# The 0/1 switch compares the base Julia image against the optional sysimage.
for enabled in 0 1; do
    echo "==== Julia sysimage enabled=$enabled ===="
    docker run --rm --platform linux/amd64 --entrypoint /bin/bash \
      -e "MASTS_USE_SYSIMAGE=$enabled" "$image" -c '
        set -euo pipefail
        cd /opt/workshop/source
        if [[ "$MASTS_USE_SYSIMAGE" = "1" && ! -f /opt/workshop/sysimages/masts-workshop.so ]]; then
          echo "No sysimage in this build; benchmark --build-arg BUILD_WORKSHOP_SYSIMAGE=1 first" >&2
          exit 1
        fi
        export MASTS_OUTPUT_DIR=/tmp/workshop-benchmark
        /usr/bin/time -f "Elapsed: %e s; peak RSS: %M KB" \
          /opt/workshop/bin/julia --threads=1 --startup-file=no --project=oceanbiome \
          oceanbiome/exercises/00_reference_column.jl --quick
      '
done
