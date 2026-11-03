#!/usr/bin/env bash
set -euo pipefail

# Verify a locally built image before sharing it or deploying to Cloud Workstations.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${1:-masts-asm-2026-modelling:local}"
output_dir="${MASTS_CONTAINER_TEST_OUTPUT:-$root/outputs/container-smoke}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

command -v docker >/dev/null || { echo 'Install Docker to run this test' >&2; exit 1; }
echo "Testing $image (results: $output_dir)"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --entrypoint /bin/bash \
    -e HOME=/tmp \
    -e JULIA_NUM_THREADS=1 \
    -e JULIA_DEPOT_PATH=/tmp/julia-depot:/opt/workshop/julia-depot \
    --mount "type=bind,source=$output_dir,target=/results" \
    "$image" -euc '
        cd /opt/workshop/source
        python -m unittest discover -s abil/tests -p "test_*.py" -v
        python -m unittest discover -s container -p "test_*.py" -v
        # The Julia extension uses 1.11 for its language server, while the
        # scientific scripts and terminal keep Julia 1.10.
        julia --startup-file=no -e "@assert VERSION == v\"1.10.12\""
        /opt/julia-ls/bin/julia --startup-file=no -e "@assert VERSION == v\"1.11.9\""
        julia --threads=1 --startup-file=no --project=oceanbiome -e \
          "using MASTSWorkshop, CairoMakie; @assert Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt) !== nothing"
        echo "Reference column (365 simulated days):"
        MASTS_OUTPUT_DIR=/results/reference /usr/bin/time -v \
          julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/00_reference_column.jl
        echo "Grazing experiments (365 simulated days each):"
        MASTS_OUTPUT_DIR=/results/grazing /usr/bin/time -v \
          julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/01_grazing.jl
        python container/check_outputs.py /results
    '

echo 'Container scientific smoke test passed.'
