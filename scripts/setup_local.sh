#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"
JULIA_BIN="${JULIA_BIN:-julia}"

command -v "$PYTHON_BIN" >/dev/null || { echo "Install Python 3.11 or set PYTHON_BIN" >&2; exit 1; }
command -v "$JULIA_BIN" >/dev/null || { echo "Install Julia 1.13.3 or set JULIA_BIN" >&2; exit 1; }
"$PYTHON_BIN" -c 'import sys; assert sys.version_info[:2] == (3, 11), "Python 3.11 is required"'
"$JULIA_BIN" --startup-file=no -e 'VERSION.major == 1 && VERSION.minor == 13 || error("Julia 1.13 is required; use Julia 1.13.3")'

"$PYTHON_BIN" -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/python" -m pip install --requirement "$ROOT/abil/requirements.txt"
"$JULIA_BIN" --startup-file=no --project="$ROOT/oceanbiome" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

printf '\nDependencies installed. Commit the generated oceanbiome/Manifest.toml to pin the resolved Julia environment.\n'
printf 'Run ./scripts/test_local.sh to verify imports and pinned versions.\n'
