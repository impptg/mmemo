#!/bin/sh
set -eu
cd "$(dirname "$0")"
python3 scripts/build-desktop.py
if [ "${1:-}" != "--build" ]; then open "$PWD/dist/mmemo.app"; fi
