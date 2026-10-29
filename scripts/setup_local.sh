#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python}"
JULIA_BIN="${JULIA_BIN:-julia}"

if [[ -z "${CONDA_PREFIX:-}" && -z "${VIRTUAL_ENV:-}" ]]; then
    echo "Activate a Python 3.11 environment first (e.g. conda activate masts-2026)" >&2
    exit 1
fi
if [[ "${CONDA_DEFAULT_ENV:-}" == "base" && -z "${VIRTUAL_ENV:-}" ]]; then
    echo "Create and activate a dedicated conda environment instead of using base" >&2
    exit 1
fi
command -v "$PYTHON_BIN" >/dev/null || { echo "Python not found: $PYTHON_BIN" >&2; exit 1; }
command -v "$JULIA_BIN" >/dev/null || { echo "Julia not found: $JULIA_BIN" >&2; exit 1; }
"$PYTHON_BIN" -c 'import sys; assert sys.version_info[:2] == (3, 11), "Python 3.11 is required"'
"$JULIA_BIN" --startup-file=no -e 'v"1.10" <= VERSION < v"2" || error("Julia 1.10 or later (1.x) is required")'

"$PYTHON_BIN" -m pip install --requirement "$ROOT/abil/requirements.txt"
JULIA_PKG_PRECOMPILE_AUTO=0 "$JULIA_BIN" --startup-file=no --project="$ROOT/oceanbiome" -e 'using Pkg; Pkg.instantiate()'

printf '\nDependencies installed. Commit the generated oceanbiome/Manifest.toml to pin the Julia environment.\n'
printf 'Run ./scripts/test_local.sh to verify imports and pinned versions.\n'
