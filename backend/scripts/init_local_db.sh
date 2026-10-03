#!/usr/bin/env bash
# One-time local Postgres setup (macOS Homebrew). Adjust for your OS if needed.
set -euo pipefail

DB_NAME="${STROLLWISE_DB_NAME:-strollwise}"
DB_USER="${STROLLWISE_DB_USER:-strollwise}"
DB_PASS="${STROLLWISE_DB_PASS:-strollwise}"

echo "Creating role and database (may prompt for your Postgres superuser password)…"
psql postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec
SQL

psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS postgis;"

echo "Done. Use:"
echo "  DATABASE_URL=postgresql+psycopg2://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
