#!/usr/bin/env bash
set -euo pipefail

# Fast acceptance test for the Abil-only workshop image.
image="${1:-masts-asm-2026-modelling:abil-only}"

docker run --rm --platform linux/amd64 \
  --entrypoint /bin/bash \
  "$image" -euc '
    cd /opt/workshop/source
    /opt/workshop/python/bin/python container/check_abil_notebooks.py
    /opt/workshop/python/bin/python -m unittest discover \
      -s abil/tests -p "test_*.py" -v
    test -f /opt/workshop/vsix/jupyter.vsix
    test -f /opt/workshop/vsix/python.vsix
    test ! -d /opt/julia
    test ! -d /opt/julia-ls
  '

echo "Abil notebook environment passed: $image"
