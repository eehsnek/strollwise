#!/usr/bin/env bash
# Reset default admin (macOS-friendly — uses project venv).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ ! -d .venv ]]; then
  echo "No .venv found. Run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi
PYTHONPATH=. .venv/bin/python scripts/reset_admin_password.py
