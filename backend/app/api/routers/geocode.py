from fastapi import APIRouter, HTTPException, Query

from app.schemas.geocode import GeocodeHit
from app.services.mapbox_geocoding_service import MapboxGeocodingService

router = APIRouter(prefix="/geocode", tags=["geocode"])


@router.get("/forward", response_model=list[GeocodeHit])
def forward_geocode(
    q: str = Query(..., min_length=2, max_length=200, description="Place name or address"),
    limit: int = Query(5, ge=1, le=10),
) -> list[GeocodeHit]:
    service = MapboxGeocodingService()
    if not service.enabled:
        raise HTTPException(
            status_code=503,
            detail="Mapbox geocoding is not configured (set MAPBOX_ACCESS_TOKEN in .env)",
        )
    hits = service.forward(q, limit=limit)
    return [
        GeocodeHit(
            name=h.name,
            place_name=h.place_name,
            lat=h.lat,
            lng=h.lng,
            relevance=h.relevance,
        )
        for h in hits
    ]
