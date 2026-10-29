#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python}"
JULIA_BIN="${JULIA_BIN:-julia}"

if [[ ! -f "$ROOT/oceanbiome/Manifest.toml" ]]; then
    echo "Missing oceanbiome/Manifest.toml; run ./scripts/setup_local.sh first" >&2
    exit 1
fi
command -v "$PYTHON_BIN" >/dev/null || { echo "Python not found: $PYTHON_BIN" >&2; exit 1; }
command -v "$JULIA_BIN" >/dev/null || { echo "Julia not found: $JULIA_BIN" >&2; exit 1; }

"$PYTHON_BIN" -m unittest discover -s "$ROOT/abil/tests" -p 'test_*.py' -v
"$JULIA_BIN" --startup-file=no --project="$ROOT/oceanbiome" "$ROOT/oceanbiome/test/runtests.jl"
