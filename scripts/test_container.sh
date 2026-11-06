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
        # Catch stale image tags immediately (e.g. after a failed docker build).
        for example in workshop/01_OceanBioME/00_reference_column.jl \
                       workshop/01_OceanBioME/01_grazing.jl \
                       workshop/01_OceanBioME/02_sinking.jl \
                       workshop/01_OceanBioME/03_remineralisation.jl \
                       workshop/01_OceanBioME/04_light_affinity.jl \
                       workshop/01_OceanBioME/05_nutrient_affinity.jl \
                       workshop/01_OceanBioME/06_phytoplankton_mortality.jl \
                       workshop/01_OceanBioME/07_bats_nabe.jl; do
            if [[ ! -f "$example" ]]; then
                echo "ERROR: $example is absent from this image. A previous Docker build may have failed; rebuild successfully before running the smoke test." >&2
                exit 1
            fi
        done
        python -m unittest discover -s abil/tests -p "test_*.py" -v
        python -m unittest discover -s container -p "test_*.py" -v
        python -m unittest discover -s scripts -p "test_*.py" -v
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
        echo "Sinking parameter experiment:"
        MASTS_OUTPUT_DIR=/results/sinking julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/02_sinking.jl
        echo "Remineralisation parameter experiment:"
        MASTS_OUTPUT_DIR=/results/remineralisation julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/03_remineralisation.jl
        echo "Light-affinity parameter experiment:"
        MASTS_OUTPUT_DIR=/results/light_affinity julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/04_light_affinity.jl
        echo "Nutrient-affinity parameter experiment:"
        MASTS_OUTPUT_DIR=/results/nutrient_affinity julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/05_nutrient_affinity.jl
        echo "Phytoplankton mortality parameter experiment:"
        MASTS_OUTPUT_DIR=/results/phytoplankton_mortality julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/06_phytoplankton_mortality.jl
        echo "Idealised Atlantic station forcing figures:"
        MASTS_OUTPUT_DIR=/results/bats_nabe \
          julia --threads=1 --startup-file=no --project=oceanbiome \
          workshop/01_OceanBioME/07_bats_nabe.jl
        test -s /results/bats_nabe/station_forcing.png
        test -s /results/bats_nabe/station_map.png
        test -s /results/bats_nabe/station_diffusivity.png
        python container/check_outputs.py /results
    '

echo 'Container scientific smoke test passed.'
