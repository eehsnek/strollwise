#!/usr/bin/env bash
# Promote a user to admin (macOS-friendly — uses project venv).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ $# -lt 1 ]]; then
  echo "Usage: ./scripts/promote_admin.sh user@example.com"
  exit 1
fi
if [[ ! -d .venv ]]; then
  echo "No .venv found. Run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi
PYTHONPATH=. .venv/bin/python scripts/promote_admin.py "$1"
