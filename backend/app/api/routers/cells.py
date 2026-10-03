from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.repositories.h3_repository import H3Repository
from app.repositories.place_repository import PlaceRepository
from app.schemas.cell import CellListItem
from app.services import h3_service
from app.utils.traveler_gradient import (
    local_ratio_from_traveler_mix,
    map_color_hex,
)
from app.utils.traveler_mix_utils import behavior_to_traveler_mix

router = APIRouter(prefix="/cells", tags=["cells"])


@router.get("", response_model=list[CellListItem])
def cells_in_viewport(
    min_lat: float = Query(..., ge=-90.0, le=90.0),
    min_lng: float = Query(..., ge=-180.0, le=180.0),
    max_lat: float = Query(..., ge=-90.0, le=90.0),
    max_lng: float = Query(..., ge=-180.0, le=180.0),
    traveler_mix: str | None = Query(default=None, max_length=16),
    place_type: str | None = Query(default=None, max_length=32),
    limit: int = Query(350, ge=1, le=600),
    db: Session = Depends(get_db),
) -> list[CellListItem]:
    cells = H3Repository(db).list_active_in_bbox(
        min_lat, min_lng, max_lat, max_lng, limit=limit * 2
    )
    place_repo = PlaceRepository(db)
    place_ids = {c.place_id for c in cells if c.place_id}
    places_by_id = (
        {p.place_id: p for p in place_repo.list_by_ids(place_ids)}
        if place_ids
        else {}
    )

    items: list[CellListItem] = []
    for cell in cells:
        lat, lng = h3_service.cell_centroid(cell.h3_index)
        if not (min_lat <= lat <= max_lat and min_lng <= lng <= max_lng):
            continue
        place = places_by_id.get(cell.place_id) if cell.place_id else None
        mix = behavior_to_traveler_mix(cell.behavior_type)
        if traveler_mix and mix != traveler_mix:
            continue
        if place_type and (place is None or place.place_type != place_type):
            continue
        local_ratio = local_ratio_from_traveler_mix(
            mix,
            local_count=cell.local_count,
            international_count=cell.international_count,
        )
        items.append(
            CellListItem(
                h3_index=cell.h3_index,
                ring=h3_service.cell_to_lnglat_ring(cell.h3_index),
                report_count=cell.report_count,
                traveler_mix=mix,
                local_ratio=round(local_ratio, 3),
                map_color=map_color_hex(local_ratio),
                function_type=cell.function_type or "unknown",
                dominant_category=cell.dominant_category,
                confidence_score=cell.confidence_score,
                crowd_score=cell.crowd_score,
                place_id=str(cell.place_id) if cell.place_id else None,
                place_name=place.display_name if place else None,
                centroid_lat=lat,
                centroid_lng=lng,
            )
        )
        if len(items) >= limit:
            break
    return items
