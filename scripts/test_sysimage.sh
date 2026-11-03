#!/usr/bin/env bash
set -euo pipefail

# Fast acceptance and startup comparison for the PackageCompiler image.
# Tests the actual workshop package, its plotting extension, and the tested
# two-day OceanBioME columns, using fresh writable depots for each mode.
image="${1:-masts-asm-2026-modelling:sysimage}"
command -v docker >/dev/null || { echo 'Docker is required to test the sysimage.' >&2; exit 1; }

echo "Checking scientific sysimage in $image"
docker run --rm --platform linux/amd64 \
  --entrypoint /bin/bash \
  -e JULIA_NUM_THREADS=1 \
  -e OPENBLAS_NUM_THREADS=1 \
  "$image" -euc '
    cd /opt/workshop/source
    image_file=/opt/workshop/sysimages/masts-workshop.so
    test -s "$image_file" || { echo "FAIL: sysimage is missing or empty: $image_file" >&2; exit 1; }
    [[ "${JULIA_NUM_PRECOMPILE_TASKS:-}" == 1 && "${OMP_NUM_THREADS:-}" == 1 && "${MKL_NUM_THREADS:-}" == 1 ]] || {
      echo "FAIL: sysimage build/runtime thread limits are not installed" >&2
      exit 1
    }

    # Verify the workshop Julia wrapper selects the sysimage by default.
    invocation="$(MASTS_REAL_JULIA=/bin/echo MASTS_USE_SYSIMAGE=1 /opt/workshop/bin/julia --version)"
    [[ "$invocation" == *"--sysimage=$image_file"* ]] || {
      echo "FAIL: workshop Julia wrapper did not select $image_file" >&2
      exit 1
    }

    # Each mode has an independent writable depot; all scientific packages
    # remain available from the precompiled, read-only image depot.
    for enabled in 1 0; do
      export MASTS_USE_SYSIMAGE="$enabled"
      export JULIA_DEPOT_PATH="/tmp/julia-sysimage-test-$enabled:/opt/workshop/julia-depot"
      echo "=== mode=$enabled: package startup and real workshop plotting ==="
      /usr/bin/time -f "Package load + plot: %e s; peak RSS: %M KB" \
        /opt/workshop/bin/julia --threads=1 --startup-file=no --project=oceanbiome \
        -e '\''using OceanBioME, Oceananigans, CairoMakie, MASTSWorkshop
             @assert Base.get_extension(MASTSWorkshop, :MASTSWorkshopMakieExt) !== nothing
             output = joinpath(mktempdir(), "physics.png")
             MASTSWorkshop.plot_idealised_physics(output)
             @assert isfile(output) && filesize(output) > 1000
             println("PASS: package imports, real Makie extension and PNG output")'\''
      echo "=== mode=$enabled: real 2-day LOBSTER column tests ==="
      /usr/bin/time -f "2-day column tests: %e s; peak RSS: %M KB" \
        /opt/workshop/bin/julia --threads=1 --startup-file=no --project=oceanbiome \
        oceanbiome/test/runtests.jl
    done
    echo "PASS: compiled sysimage and regular Julia both ran real workshop physics and plotting"
  '
