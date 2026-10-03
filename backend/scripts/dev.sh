#!/usr/bin/env bash
# Run API locally: venv, migrations, uvicorn (no Docker).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt
fi
# shellcheck disable=SC1091
source .venv/bin/activate

if [[ -f .env ]]; then
  set -a && source .env && set +a
elif [[ -f .env.example ]]; then
  set -a && source .env.example && set +a
fi

python -m alembic upgrade head
exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
