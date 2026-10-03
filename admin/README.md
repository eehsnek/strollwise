# StrollWise Admin

Separate web dashboard for researchers and operators. Implements the thesis **Review Pending Tags** use case plus zone validation, user management, analytics export, catalog editing, and pipeline controls.

## Prerequisites

- Backend API running at `http://127.0.0.1:8000` (see [`../backend/README.md`](../backend/README.md))
- Node.js 18+

## Setup

```bash
cd admin
npm install
cp .env.example .env   # optional — defaults to local API
npm run dev
```

Open [http://localhost:5173](http://localhost:5173).

## Default admin account (after seed)

| Field | Value |
| --- | --- |
| Email | `admin@strollwise.dev` |
| Password | `admin123456` |

Create or promote admins:

```bash
cd backend
./scripts/reset_admin.sh
# or: PYTHONPATH=. .venv/bin/python scripts/reset_admin_password.py
```

Create or promote admins:

```bash
cd backend
./scripts/promote_admin.sh your@email.com
```

## Environment

| Variable | Default |
| --- | --- |
| `VITE_API_URL` | `http://127.0.0.1:8000` |

## Screens

| Route | Purpose |
| --- | --- |
| `/login` | Admin JWT login |
| `/` | Dashboard stats |
| `/moderation` | Pending/flagged report queue |
| `/zones` | Zone validation list |
| `/users` | User management |
| `/catalog` | Cebu zone catalog |
| `/analytics` | Charts + CSV/JSON export |
| `/pipeline` | Rebuild aggregates/places/zones |
| `/settings` | Runtime validation thresholds |
| `/audit` | Audit log viewer |

## Live sync with the mobile app

The admin console reads the same PostgreSQL data the Flutter app writes (`POST /api/v1/reports`, zone merges, etc.).

- **SSE stream:** `GET /api/v1/admin/events?token=<jwt>` pushes `report.created`, `report.approved`, `zones.updated`, and related events when the mobile app submits tags or the pipeline runs.
- **Polling fallback:** Dashboard, moderation, zones, and audit pages also refetch every 15–60s if SSE is unavailable.
- **Catalog sync:** Admin catalog edits are loaded from the DB by the backend zone/places API (same data pipeline the mobile map uses after cache expiry).

The sidebar shows **Live — mobile sync** when connected to the event stream.

The admin dashboard uses the same brand palette and logo as the Flutter app (`frontend/lib/app/theme/colors.dart`, `strollwiselogo.jpg`).

## Build

```bash
npm run build
npm run preview
```
