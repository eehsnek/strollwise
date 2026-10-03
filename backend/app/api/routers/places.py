from __future__ import annotations

import logging
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.cache import build_viewport_cache_key, cache_get, cache_set
from app.core.config import settings
from app.core.database import get_db
from app.repositories.place_repository import PlaceRepository
from app.schemas.common import Centroid
from app.schemas.place import PlaceDetail, PlaceListItem, PlaceSummary
from app.schemas.place_recommendation import PlaceRecommendation
from app.services.place_recommendations_service import fetch_place_recommendations
from app.services.place_catalog import CEBU_PLACE_CATALOG
from app.services.place_service import PlaceService
from app.utils.geo_utils import polygon_intersects_bbox
from app.utils.h3_display import display_h3_rings
from app.utils.place_geometry import point_in_geojson

log = logging.getLogger(__name__)

router = APIRouter(prefix="/places", tags=["places"])


@router.get("", response_model=list[PlaceListItem])
def places_in_viewport(
    min_lat: float = Query(..., ge=-90.0, le=90.0),
    min_lng: float = Query(..., ge=-180.0, le=180.0),
    max_lat: float = Query(..., ge=-90.0, le=90.0),
    max_lng: float = Query(..., ge=-180.0, le=180.0),
    place_type: str | None = Query(default=None, max_length=32),
    db: Session = Depends(get_db),
) -> list[PlaceListItem]:
    if min_lat > max_lat or min_lng > max_lng:
        raise HTTPException(status_code=400, detail="Invalid bounding box")

    cache_key = build_viewport_cache_key(
        min_lat, min_lng, max_lat, max_lng, zoom=None, filter_key=f"places:{place_type}"
    )
    cached = cache_get(cache_key)
    if cached is not None:
        return [PlaceListItem.model_validate(item) for item in cached]

    repo = PlaceRepository(db)
    in_viewport = [
        p
        for p in repo.list_active()
        if _place_in_bbox(p, min_lat, min_lng, max_lat, max_lng)
        and (place_type is None or p.place_type == place_type.lower())
    ]
    in_viewport.sort(key=lambda p: p.report_count, reverse=True)
    response = [_to_list_item(p) for p in in_viewport]
    cache_set(
        cache_key,
        [item.model_dump(mode="json") for item in response],
        settings.cache_ttl_zones_seconds,
    )
    return response


@router.get("/recommendations", response_model=list[PlaceRecommendation])
def place_recommendations(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    vibe: str = Query(
        "food",
        description="food | cafe | nightlife | tourist | nature | budget",
    ),
    area_label: str = Query("Cebu City", min_length=1, max_length=120),
    limit: int = Query(8, ge=1, le=15),
) -> list[PlaceRecommendation]:
    """Curated top places to visit near a Cebu area for a given vibe."""
    return fetch_place_recommendations(
        lat=lat,
        lng=lng,
        vibe=vibe.strip().lower(),
        area_label=area_label.strip(),
        limit=limit,
    )


@router.get("/resolve", response_model=Optional[PlaceSummary])
def resolve_place_at_point(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    db: Session = Depends(get_db),
) -> Optional[PlaceSummary]:
    """Return the catalog place containing this point, if any."""
    PlaceService(db).sync_catalog_places()
    repo = PlaceRepository(db)
    for entry in CEBU_PLACE_CATALOG:
        if not point_in_geojson(entry.polygon_geojson, lat=lat, lng=lng):
            continue
        place = repo.get_by_slug(entry.slug)
        if place is None:
            continue
        return PlaceSummary(
            place_id=place.place_id,
            display_name=place.display_name,
            place_type=place.place_type,
            report_count=place.report_count,
            confidence_score=place.confidence_score,
        )
    return None


@router.get("/{place_id}", response_model=PlaceDetail)
def place_detail(place_id: UUID, db: Session = Depends(get_db)) -> PlaceDetail:
    repo = PlaceRepository(db)
    place = repo.get(place_id)
    if place is None:
        raise HTTPException(status_code=404, detail="Place not found")
    cells = len(place.source_h3_indexes_json or [])
    top_tags: list[str] = []
    return PlaceDetail(
        place_id=place.place_id,
        display_name=place.display_name,
        place_type=place.place_type,
        polygon_geojson=place.polygon_geojson,
        centroid=Centroid(lat=place.centroid_lat, lng=place.centroid_lng),
        report_count=place.report_count,
        confidence_score=place.confidence_score,
        cell_count=cells,
        source_h3_rings=display_h3_rings(place.source_h3_indexes_json),
        source_h3_indexes=list(place.source_h3_indexes_json or []),
        top_tags=top_tags,
        updated_at=place.updated_at,
    )


def _place_in_bbox(
    place, min_lat: float, min_lng: float, max_lat: float, max_lng: float
) -> bool:
    from app.api.routers.zones import _flatten_polygon_rings

    rings = _flatten_polygon_rings(place.polygon_geojson)
    return polygon_intersects_bbox(rings, min_lat, min_lng, max_lat, max_lng)


def _to_list_item(place) -> PlaceListItem:
    return PlaceListItem(
        place_id=place.place_id,
        display_name=place.display_name,
        place_type=place.place_type,
        polygon_geojson=place.polygon_geojson,
        centroid=Centroid(lat=place.centroid_lat, lng=place.centroid_lng),
        report_count=place.report_count,
        confidence_score=place.confidence_score,
        cell_count=len(place.source_h3_indexes_json or []),
        source_h3_rings=display_h3_rings(place.source_h3_indexes_json),
        updated_at=place.updated_at,
    )
