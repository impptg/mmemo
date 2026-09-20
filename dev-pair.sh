#!/bin/sh
set -eu
cd "$(dirname "$0")"
./run.sh --build
python3 scripts/prepare-pair.py
if [ "${1:-}" != "--prepare" ]; then
  open "$PWD/dist/mmemo-user_pptg.app" --args --show
  open "$PWD/dist/mmemo-user_mm.app" --args --show
fi
