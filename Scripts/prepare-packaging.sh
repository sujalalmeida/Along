#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$PROJECT_ROOT/.build/packaging"
mkdir -p "$TOOLS/wheels"
if [[ ! -x "$TOOLS/venv/bin/python" ]]; then python3 -m venv "$TOOLS/venv"; fi
# curl uses the host's certificate store; pip installs locally with pinned hashes.
if [[ ! -f "$TOOLS/wheels/ds_store-1.3.3-py3-none-any.whl" ]]; then
    curl --fail --location --proto '=https' --tlsv1.2 'https://files.pythonhosted.org/packages/66/c0/718a4132306ff8ff052f2c40595f45595993b480409400d55b07f3842d45/ds_store-1.3.3-py3-none-any.whl' -o "$TOOLS/wheels/ds_store-1.3.3-py3-none-any.whl"
fi
if [[ ! -f "$TOOLS/wheels/mac_alias-2.2.3-py3-none-any.whl" ]]; then
    curl --fail --location --proto '=https' --tlsv1.2 'https://files.pythonhosted.org/packages/13/20/103f4e4a6e8a524ea92eee7d938c6133d0b129aa999a50f8648ad126c728/mac_alias-2.2.3-py3-none-any.whl' -o "$TOOLS/wheels/mac_alias-2.2.3-py3-none-any.whl"
fi
"$TOOLS/venv/bin/python" -m pip install --disable-pip-version-check --no-index --find-links "$TOOLS/wheels" --require-hashes -r "$PROJECT_ROOT/Scripts/packaging-requirements.txt"
