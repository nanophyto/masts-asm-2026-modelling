#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JULIA_BIN="${JULIA_BIN:-julia}"

if [[ ! -f "$ROOT/oceanbiome/Manifest.toml" ]]; then
    echo "Missing oceanbiome/Manifest.toml; run ./scripts/setup_local.sh first" >&2
    exit 1
fi
if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
    echo "Missing .venv; run ./scripts/setup_local.sh first" >&2
    exit 1
fi

"$ROOT/.venv/bin/python" -m unittest discover -s "$ROOT/abil/tests" -p 'test_*.py' -v
"$JULIA_BIN" --startup-file=no --project="$ROOT/oceanbiome" "$ROOT/oceanbiome/test/runtests.jl"
