<<<<<<< HEAD
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
=======
# strollwise
StrollWise Core Modules

1. H3-based Zone Engine
Definition:
The map is divided into hexagonal cells using H3
Each hex stores all activity inside its area
Hex grid removes irregular shapes from raw GPS data
Explanation:
Hexagons are the most ideal polygon shape
Requirements
• H3 library
• GPS input stream
• Resolution level control
• Mapping from lat long to hex ID
Key data inside each hex
• Number of reports
• Activity types
• Time distribution*
• Local vs international ratio
Features
• Batch-time zone updates
• Zone classification
• Density scoring
• Input for clustering module
User flow
• User walks or travels
• GPS captured every few seconds
• Each coordinate mapped to a hex
• Hex updates count and activity

H3 hexagonal maps serve as a benchmark for converting raw GPS noise into structured spatial intelligence units.

2. User Pinning
Raw GPS exposes user activity. GPS coordinates are converted into a hex ID for privacy. Users can pin hex into various activities such as food, shopping, sightseeing, nightlife, and transit.
Requirements
• Tag input interface
• Activity category list
• Timestamp logging
• Optional photo upload
Features:
Check in system where the users must be or were at the location to pin it
Approximate location (hex) and time period
Users can make their pin public, private, or anonymous

3. Cluster Algorithm and Aggregation
Mechanics:
A hex is visible if multiple users tag the same area
A user may check in a cluster to view detailed information about the zone, since zones cannot be generalized into a single definition.
Example: 50 users tag this hex as ‘food’; therefore, the system marks the hex as a food hotspot
Requirements:
If the number of users >= threshold value, then the zone is visible
The dominant tag defines the primary zone characteristic
Possible Algorithms:
DBSCAN for density clustering (finds clusters without a pre-defined number?, handles noise?, irregular travel patterns?)
K-nearest neighbor for refinement
There must be an algorithm where clusters can merge, with a max limit logic, and split if density drops.

Clustering converts raw movement data into behavioral spatial information.

4. Backend Database
Recommended Database Systems:
AWS DynamoDB (might be paid)

Tables & Data:
User Profiles (age range, type (lcl, intl), nationality, gender)
GPS coordinates
Hex id
Cluster id
Tags and activities
// I was thinking that the display information should be batch-time instead of real-time, which could be used as a test case to prevent " tagging attacks.

The backend ensures scalable, real-time data processing and batch-time information display.

5. Mapping API - converting back-end data into the Map UI
Recommended Systems:
✅ Leaflet.js (free, simple, prototype)
Mapbox
Google & Apple Maps (very expensive)
Requirements:
• API key
• Map SDK integration
• Layer configuration
Features:
Colored zones by local, international, and all (including mixed)
Heatmap visualization
Zone markers (this is a food hotspot)
Routing?
Layer examples
• Zone layer
• Traffic layer
• Hotspot layer
• Route layer
User flow
• User opens app
• Map loads
• Backend sends data
• Map renders zones and clusters

Map API translates data into an interactive visual experience.

FULL SYSTEM FLOW
Step by step
• User moves
• GPS collected
• Data mapped to H3 hex
• User tags activity
• Hex data updated
• Clustering runs
• Clusters stored
• Map displays results
Key innovation flow
Raw GPS → Hex zones → Tagged data → Clusters → Visual map

StrollWise converts raw movement into structured travel intelligence using H3 zoning, crowd-sourced tagging, and density-based clustering, then visualizes it in real time through an interactive map system.
>>>>>>> 2dbfa765641d6514838ad74a402318ec0862d7d4
