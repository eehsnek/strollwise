# StrollWise Backend

FastAPI + PostgreSQL (PostGIS) + optional Redis for StrollWise.

## Tech stack

- Python 3.11+
- FastAPI, SQLAlchemy 2.x, Alembic
- PostgreSQL with PostGIS
- Redis (optional — cache degrades gracefully if unavailable)
- h3-py, Passlib, python-jose

## Layout

```
backend/
  app/               routers, services, models, schemas
  alembic/           migrations
  tests/             pytest (SQLite, no Postgres required)
  seed.py            demo Cebu data
  scripts/
    dev.sh           venv + migrate + uvicorn
    init_local_db.sh one-time Postgres/PostGIS setup
```

## Quick start (local only)

### Prerequisites

Install and start **PostgreSQL + PostGIS** and **Redis** on your machine.

**macOS (Homebrew):**

```bash
brew install postgresql@16 postgis redis
brew services start postgresql@16
brew services start redis
./scripts/init_local_db.sh
```

### API

```bash
cd backend
cp .env.example .env
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m alembic upgrade head
python seed.py
uvicorn app.main:app --reload
```

Or: `./scripts/dev.sh`

API: `http://localhost:8000` — docs at `/docs`.

## Environment variables

See `.env.example`. Defaults target **localhost**:

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Postgres/PostGIS connection |
| `REDIS_URL` | Redis cache (optional at runtime) |
| `JWT_SECRET_KEY` | JWT signing |
| `H3_RESOLUTION` | Cell resolution (default 8) |

`app/core/config.py` and `alembic.ini` also default to `localhost:5432` if `.env` is missing.

## Migrations

```bash
python -m alembic upgrade head
python -m alembic revision -m "description" --autogenerate
```

## Seed data

```bash
python seed.py
```

Seeds users and reports around Cebu catalog places, then rebuilds places and zones.

## Tests

```bash
pytest -q
```

No live Postgres needed for the test suite.

## API overview (`/api/v1/...`)

| Method | Path | Description |
| --- | --- | --- |
| POST | `/auth/register`, `/auth/login` | Account + JWT |
| GET | `/auth/me`, `/users/me` | Profile |
| POST | `/reports` | Submit tag |
| GET | `/zones` | Map viewport zones |
| GET | `/zones/{zone_id}` | Zone detail |
| GET | `/places` | Catalog places in viewport |
| GET | `/places/resolve` | Place at lat/lng |
| GET | `/analytics/city-pulse` | City summary |

Admin routes (`/admin/*`, requires `is_admin`): moderation queue, zones, users, analytics export, catalog CRUD, pipeline rebuild, runtime config, audit log. See [`admin/README.md`](../admin/README.md).

## Caching

Redis caches `/zones` and analytics. If Redis is not running, routes still work; cache helpers no-op after the first connection failure.
