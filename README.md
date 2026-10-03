# StrollWise

StrollWise is a crowd-sourced travel intelligence app. It uses **H3** hex cells to aggregate reports into **map-ready zones** (traveler mix + place type) without exposing individual trajectories in public APIs.

## Architecture

```text
Flutter (iOS, Android, desktop, web)     admin/ (React web dashboard)
        |  REST (Dio), JWT auth                    |  REST, JWT
        v                                          v
FastAPI  —  SQLAlchemy / GeoAlchemy2  —  PostgreSQL + PostGIS
        |
        +—  Redis (optional cache; app runs without it)
        +—  Local disk or S3 (optional image uploads)
```

## Prerequisites

- **Python 3.11+** (3.9 may work but 3.11+ is recommended)
- **PostgreSQL 16+ with PostGIS** (local install, e.g. Homebrew)
- **Redis** (optional — improves caching; API works if Redis is down)
- **Flutter** for the mobile app ([`frontend/pubspec.yaml`](frontend/pubspec.yaml))

## Local setup

### 1) PostgreSQL + PostGIS + Redis (macOS example)

```bash
brew install postgresql@16 postgis redis
brew services start postgresql@16
brew services start redis
```

Create the app database once:

```bash
chmod +x backend/scripts/init_local_db.sh
./backend/scripts/init_local_db.sh
```

### 2) Backend API

```bash
cd backend
cp .env.example .env          # uses localhost URLs
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m alembic upgrade head
python seed.py                  # demo Cebu data (keeps your registered accounts)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Or use the helper script (venv + migrate + server):

```bash
chmod +x backend/scripts/dev.sh
./backend/scripts/dev.sh
```

- API: [http://localhost:8000](http://localhost:8000)
- OpenAPI: [http://localhost:8000/docs](http://localhost:8000/docs)
- Health: `GET http://localhost:8000/health`

### 3) Flutter app

```bash
cd frontend
flutter pub get
flutter run --dart-define=API_URL=http://127.0.0.1:8000
```

**Mapbox (optional)** — Map style + place search geocoding. Without a token the app uses Carto Positron and OpenStreetMap Nominatim.

```bash
# Same token as in backend/.env (public pk.* token is fine for client maps)
flutter run \
  --dart-define=API_URL=http://127.0.0.1:8000 \
  --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_token_here
```

Verify catalog zone centers against Mapbox (backend):

```bash
cd backend
# set MAPBOX_ACCESS_TOKEN in .env first
python scripts/verify_zone_placements_mapbox.py
```

- **iOS Simulator:** `http://127.0.0.1:8000` or `http://localhost:8000`
- **Android emulator:** `http://10.0.2.2:8000`
- **Physical device:** your Mac’s LAN IP, e.g. `http://192.168.1.x:8000`

### 4) Admin dashboard

```bash
cd admin
npm install
npm run dev
# VITE_API_URL=http://127.0.0.1:8000
```

Login with the seeded admin (`admin@strollwise.dev` / `admin123456` after `python seed.py`). See [`admin/README.md`](admin/README.md).

## Repository layout

| Path | Role |
| --- | --- |
| `frontend/` | Flutter app (Explore, tags, feed, profile) |
| `admin/` | React web admin dashboard (moderation, analytics, pipeline) |
| `backend/` | FastAPI, Alembic, `seed.py`, tests |
| `backend/scripts/` | `dev.sh`, `init_local_db.sh`, `promote_admin.py` |

Details: [`backend/README.md`](backend/README.md).

## Tests

```bash
cd backend && pytest -q
```

Tests use in-memory SQLite — no Postgres required for pytest.

## Environment

Copy [`backend/.env.example`](backend/.env.example) to `backend/.env`. Key values:

| Variable | Local default |
| --- | --- |
| `DATABASE_URL` | `postgresql+psycopg2://strollwise:strollwise@localhost:5432/strollwise` |
| `REDIS_URL` | `redis://localhost:6379/0` |
| `MAPBOX_ACCESS_TOKEN` | Optional — geocoding API + placement verification |

## Pipeline (short)

1. `POST /api/v1/reports` → H3 cell + pending validation  
2. Approved reports → cell aggregates → places → zones (`traveler_mix`, linked place)  
3. Explore loads `GET /api/v1/zones` and `GET /api/v1/places`
