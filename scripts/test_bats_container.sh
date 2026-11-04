#!/usr/bin/env bash
set -euo pipefail

# End-to-end check of the upstream BATS example in a disposable writable folder.
# Full training includes RF, XGBoost, and KNN and is intentionally opt-in.
image="${1:-masts-asm-2026-modelling:pr4-bats}"

docker run --rm --platform linux/amd64 \
  --entrypoint /bin/bash \
  -e MPLBACKEND=Agg \
  -e OMP_NUM_THREADS=2 \
  -e OPENBLAS_NUM_THREADS=1 \
  "$image" -euc '
    cp -a /opt/workshop/source/workshop/02_Abil /tmp/bats-example
    cd /tmp/bats-example
    /opt/workshop/python/bin/python regressor.py
    for file in BATS_observations.png BATS_environment.png BATS_predictions.png BATS_obs_preds.png \
                ModelOutput/regressor/posts/BATS_mean_abundance.nc \
                ModelOutput/regressor/posts/BATS_ci95_UL_abundance.nc \
                ModelOutput/regressor/posts/BATS_ci95_LL_abundance.nc; do
      test -s "$file" || { echo "Missing BATS result: $file" >&2; exit 1; }
    done
    echo "BATS regressor end-to-end outputs verified."
  '
