from __future__ import annotations

import logging
import uuid
from types import SimpleNamespace
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.cache import (
    build_viewport_cache_key,
    build_zone_feed_cache_key,
    cache_get,
    cache_set,
)
from app.core.config import settings
from app.core.database import get_db
from app.repositories.place_repository import PlaceRepository
from app.repositories.zone_repository import ZoneRepository
from app.schemas.common import Centroid
from app.models.enums import BehaviorType, FunctionType, LiveStatus
from app.schemas.place import PlaceSummary
from app.schemas.zone import CurrentZoneOverview, ZoneDetail, ZoneLaunchContext, ZoneListItem
from app.services.place_catalog import catalog_place_at_point_db
from app.services.zone_catalog import (
    catalog_entry_for_name,
    default_local_ratio_for_name,
    nearest_catalog_entry,
)
from app.utils.place_geometry import point_in_geojson
from app.utils.traveler_gradient import (
    local_ratio_from_traveler_mix,
    map_color_hex,
)
from app.utils.traveler_mix_utils import behavior_to_traveler_mix
from app.services.ranking_service import RankingService
from app.services import h3_service
from app.utils.geo_utils import haversine_km, polygon_intersects_bbox
from app.utils.h3_display import display_h3_rings, zone_display_rings

log = logging.getLogger(__name__)

router = APIRouter(prefix="/zones", tags=["zones"])


@router.get("", response_model=list[ZoneListItem])
def zones_in_viewport(
    min_lat: float = Query(..., ge=-90.0, le=90.0),
    min_lng: float = Query(..., ge=-180.0, le=180.0),
    max_lat: float = Query(..., ge=-90.0, le=90.0),
    max_lng: float = Query(..., ge=-180.0, le=180.0),
    zoom: float | None = Query(default=None, ge=0, le=22),
    filter: str | None = Query(default=None, max_length=32),
    traveler_mix: str | None = Query(default=None, max_length=16),
    place_type: str | None = Query(default=None, max_length=32),
    user_lat: float | None = Query(default=None, ge=-90.0, le=90.0),
    user_lng: float | None = Query(default=None, ge=-180.0, le=180.0),
    db: Session = Depends(get_db),
) -> list[ZoneListItem]:
    if min_lat > max_lat or min_lng > max_lng:
        raise HTTPException(status_code=400, detail="Invalid bounding box")

    cache_key = build_viewport_cache_key(
        min_lat,
        min_lng,
        max_lat,
        max_lng,
        zoom=zoom,
        filter_key=filter,
        traveler_mix=traveler_mix,
        place_type=place_type,
    )
    cached = cache_get(cache_key)
    if cached is not None:
        return [ZoneListItem.model_validate(item) for item in cached]

    repo = ZoneRepository(db)
    # Fast path: ask PostGIS via ST_Intersects.
    in_viewport = repo.list_active_in_bbox(min_lat, min_lng, max_lat, max_lng)
    if in_viewport is None or not in_viewport:
        # Fallback when PostGIS is unavailable or polygon_geometry is missing on rows.
        in_viewport = [
            z
            for z in repo.list_active()
            if polygon_intersects_bbox(
                _flatten_polygon_rings(z.polygon_geojson),
                min_lat,
                min_lng,
                max_lat,
                max_lng,
            )
        ]
    _attach_place_metadata(db, in_viewport)
    in_viewport = _filter_catalog_zones(db, in_viewport)
    ranked = RankingService.apply_viewport_filters(
        in_viewport,
        filter_key=filter,
        traveler_mix=traveler_mix,
        place_type=place_type,
        user_lat=user_lat,
        user_lng=user_lng,
    )
    response = [_to_list_item(z) for z in ranked]
    cache_set(
        cache_key,
        [item.model_dump(mode="json") for item in response],
        settings.cache_ttl_zones_seconds,
    )
    return response


@router.get("/feed", response_model=list[ZoneListItem])
def zones_feed(
    limit: int = Query(40, ge=1, le=100),
    filter: str | None = Query(default=None, max_length=32),
    user_lat: float | None = Query(default=None, ge=-90.0, le=90.0),
    user_lng: float | None = Query(default=None, ge=-180.0, le=180.0),
    db: Session = Depends(get_db),
) -> list[ZoneListItem]:
    """Ranked zone list for the feed (global city list, not viewport-clipped)."""
    cache_key = build_zone_feed_cache_key(limit, filter, user_lat, user_lng)
    cached = cache_get(cache_key)
    if cached is not None:
        return [ZoneListItem.model_validate(item) for item in cached]

    repo = ZoneRepository(db)
    all_zones = repo.list_active()
    _attach_place_metadata(db, all_zones)
    all_zones = _filter_catalog_zones(db, all_zones)
    ranked = RankingService.rank(
        all_zones,
        filter_key=filter,
        user_lat=user_lat,
        user_lng=user_lng,
        limit=limit,
    )
    response = [_to_list_item(z) for z in ranked]
    cache_set(
        cache_key,
        [item.model_dump(mode="json") for item in response],
        settings.cache_ttl_zone_feed_seconds,
    )
    return response


@router.get("/current", response_model=CurrentZoneOverview)
def current_zone_overview(
    lat: float = Query(..., ge=-90.0, le=90.0),
    lng: float = Query(..., ge=-180.0, le=180.0),
    ring: int = Query(1, ge=1, le=2),
    limit: int = Query(8, ge=1, le=20),
    db: Session = Depends(get_db),
) -> CurrentZoneOverview:
    repo = ZoneRepository(db)
    zones = repo.list_active()
    _attach_place_metadata(db, zones)
    zones = _filter_catalog_zones(db, zones)
    if not zones:
        return CurrentZoneOverview(
            current_zone=None,
            nearby_zones=[],
            alternative_zones=[],
            context=ZoneLaunchContext(
                city_activity="quiet",
                crowd_level_percent=0,
                local_presence_percent=0,
                peak_time_window=None,
            ),
        )

    current = _find_current_zone(db, zones, lat=lat, lng=lng)
    exclude_nearby: set[UUID] = set()
    if current is not None:
        exclude_nearby.add(current.zone_id)
        mixed_ids = getattr(current, "_mixed_component_zone_ids", None)
        if mixed_ids:
            exclude_nearby.update(mixed_ids)
    nearby = _nearby_ranked(
        zones,
        lat=lat,
        lng=lng,
        exclude_zone_ids=exclude_nearby,
        limit=limit,
        radius_km=2.4 if ring == 1 else 4.8,
    )
    alternatives = (
        RankingService.recommend_alternatives(current, nearby + ([current] if current else []))
        if current is not None and current.crowd_level >= 0.6
        else []
    )
    context_source = current if current is not None else nearby[0]
    city_activity = _city_activity_label(context_source.crowd_level)
    crowd_percent = min(max(context_source.crowd_level * 100, 0), 100)

    overview_zones = [z for z in [current, *nearby, *alternatives] if z is not None]
    _attach_place_metadata(db, overview_zones)

    return CurrentZoneOverview(
        current_zone=_to_list_item(current) if current is not None else None,
        nearby_zones=[_to_list_item(z) for z in nearby],
        alternative_zones=[_to_list_item(z) for z in alternatives],
        context=ZoneLaunchContext(
            city_activity=city_activity,
            crowd_level_percent=round(crowd_percent, 1),
            local_presence_percent=round(context_source.local_presence_percent, 1),
            peak_time_window=context_source.peak_time_label,
        ),
    )


@router.get("/{zone_id}", response_model=ZoneDetail)
def zone_detail(zone_id: UUID, db: Session = Depends(get_db)) -> ZoneDetail:
    repo = ZoneRepository(db)
    zone = repo.get(zone_id)
    if zone is None:
        raise HTTPException(status_code=404, detail="Zone not found")

    nearby = _nearby_zone_ids(repo, zone)
    place_repo = PlaceRepository(db)
    primary_place = place_repo.get(zone.place_id) if zone.place_id else None
    places_here = _places_for_zone_detail(place_repo, zone, primary_place)
    mix, place_name, place_type = _zone_place_fields(zone, primary_place)
    local_ratio = _zone_local_ratio(zone, mix)
    return ZoneDetail(
        zone_id=zone.zone_id,
        display_name=zone.display_name,
        behavior_type=zone.behavior_type,
        traveler_mix=mix,
        function_type=zone.function_type,
        place_id=zone.place_id,
        place_name=place_name,
        place_type=place_type,
        places=places_here,
        summary=zone.summary,
        live_status=zone.live_status,
        polygon_geojson=zone.polygon_geojson,
        centroid=Centroid(lat=zone.centroid_lat, lng=zone.centroid_lng),
        crowd_level=zone.crowd_level,
        local_presence_percent=zone.local_presence_percent,
        local_ratio=round(local_ratio, 3),
        map_color=map_color_hex(local_ratio),
        peak_time_label=zone.peak_time_label,
        top_activities=list(zone.top_activities_json or []),
        confidence_score=zone.confidence_score,
        why_visit=_why_visit(zone),
        live_update=_live_update(zone),
        nearby_zone_ids=nearby,
        source_h3_indexes=list(zone.source_h3_indexes_json or []),
        source_h3_rings=zone_display_rings(
            zone.polygon_geojson,
            zone.source_h3_indexes_json,
        ),
        report_count=zone.report_count,
        updated_at=zone.updated_at,
    )


@router.get("/{zone_id}/nearby", response_model=list[ZoneListItem])
def zone_nearby(
    zone_id: UUID,
    radius_km: float = Query(3.0, gt=0, le=25.0),
    limit: int = Query(10, ge=1, le=40),
    db: Session = Depends(get_db),
) -> list[ZoneListItem]:
    repo = ZoneRepository(db)
    zone = repo.get(zone_id)
    if zone is None:
        raise HTTPException(status_code=404, detail="Zone not found")
    all_zones = repo.list_active()
    distances: list[tuple[float, object]] = []
    for other in all_zones:
        if other.zone_id == zone.zone_id:
            continue
        d = haversine_km(
            zone.centroid_lat, zone.centroid_lng, other.centroid_lat, other.centroid_lng
        )
        if d <= radius_km:
            distances.append((d, other))
    distances.sort(key=lambda pair: pair[0])
    return [_to_list_item(o) for _, o in distances[:limit]]


def _catalog_slugs(db: Session) -> set[str]:
    from app.services.zone_catalog import load_catalog_from_db

    return {entry.zone_id.lower() for entry in load_catalog_from_db(db)}


def _filter_catalog_zones(db: Session, zones: list) -> list:
    """Only curated thesis zones (one per catalog place)."""
    slugs = _catalog_slugs(db)
    filtered = []
    for zone in zones:
        slug = getattr(zone, "_place_slug", None)
        if slug in slugs:
            filtered.append(zone)
    return filtered


def _attach_place_metadata(db: Session, zones: list) -> None:
    place_ids = {z.place_id for z in zones if z.place_id}
    if not place_ids:
        return
    place_repo = PlaceRepository(db)
    by_id = {p.place_id: p for p in place_repo.list_by_ids(place_ids)}
    for zone in zones:
        place = by_id.get(zone.place_id)
        if place is None:
            continue
        zone._place_display_name = place.display_name  # type: ignore[attr-defined]
        zone._place_type = place.place_type  # type: ignore[attr-defined]
        zone._place_slug = place.slug  # type: ignore[attr-defined]


def _zone_place_fields(zone, primary_place) -> tuple[str, str | None, str | None]:
    mix = zone.traveler_mix or behavior_to_traveler_mix(zone.behavior_type)
    if primary_place is None:
        return mix, None, None
    return mix, primary_place.display_name, primary_place.place_type


def _places_for_zone_detail(place_repo, zone, primary_place) -> list[PlaceSummary]:
    items: list[PlaceSummary] = []
    if primary_place is not None:
        items.append(
            PlaceSummary(
                place_id=primary_place.place_id,
                display_name=primary_place.display_name,
                place_type=primary_place.place_type,
                report_count=primary_place.report_count,
                confidence_score=primary_place.confidence_score,
            )
        )
    for other in place_repo.list_active():
        if primary_place and other.place_id == primary_place.place_id:
            continue
        d = haversine_km(
            zone.centroid_lat,
            zone.centroid_lng,
            other.centroid_lat,
            other.centroid_lng,
        )
        if d <= 0.6:
            items.append(
                PlaceSummary(
                    place_id=other.place_id,
                    display_name=other.display_name,
                    place_type=other.place_type,
                    report_count=other.report_count,
                    confidence_score=other.confidence_score,
                )
            )
    return items[:6]


def _zone_local_ratio(zone, mix: str) -> float:
    pct = float(zone.local_presence_percent or 0.0)
    if pct > 0:
        return local_ratio_from_traveler_mix(mix, local_presence_percent=pct)
    return default_local_ratio_for_name(zone.display_name, mix, pct)


def _to_list_item(zone) -> ZoneListItem:
    mix = zone.traveler_mix or behavior_to_traveler_mix(zone.behavior_type)
    place_name = getattr(zone, "_place_display_name", None)
    place_type = getattr(zone, "_place_type", None)
    local_ratio = _zone_local_ratio(zone, mix)
    return ZoneListItem(
        zone_id=zone.zone_id,
        display_name=zone.display_name,
        behavior_type=zone.behavior_type,
        traveler_mix=mix,
        function_type=zone.function_type,
        place_id=zone.place_id,
        place_name=place_name,
        place_type=place_type,
        summary=zone.summary,
        live_status=zone.live_status,
        polygon_geojson=zone.polygon_geojson,
        centroid=Centroid(lat=zone.centroid_lat, lng=zone.centroid_lng),
        crowd_level=zone.crowd_level,
        local_presence_percent=zone.local_presence_percent,
        local_ratio=round(local_ratio, 3),
        map_color=map_color_hex(local_ratio),
        peak_time_label=zone.peak_time_label,
        confidence_score=zone.confidence_score,
        priority_score=zone.priority_score,
        source_h3_rings=zone_display_rings(
            zone.polygon_geojson,
            zone.source_h3_indexes_json,
        ),
        updated_at=zone.updated_at,
    )


def _ring_bbox_area_deg2(ring: list[list[float]]) -> float:
    if len(ring) < 3:
        return 1e9
    lngs = [p[0] for p in ring]
    lats = [p[1] for p in ring]
    w = max(lngs) - min(lngs)
    h = max(lats) - min(lats)
    return max(w * h, 1e-12)


def _geojson_bbox_area_deg2(geojson: dict | None) -> float:
    """Rough footprint of zone geometry; smaller = more local / street-scale."""
    if not geojson or not isinstance(geojson, dict):
        return 1e9
    geom_type = geojson.get("type")
    coords = geojson.get("coordinates", [])
    if geom_type == "Polygon" and coords and coords[0]:
        return _ring_bbox_area_deg2(coords[0])
    if geom_type == "MultiPolygon":
        total = 0.0
        for poly in coords:
            if poly and poly[0]:
                total += _ring_bbox_area_deg2(poly[0])
        return total if total > 0 else 1e9
    return 1e9


def _catalog_place_at_point(db: Session, *, lat: float, lng: float):
    return catalog_place_at_point_db(db, lat=lat, lng=lng)


def _zone_for_catalog_place(
    zones: list, entry, *, lat: float, lng: float
) -> object | None:
    """Match a merged zone to a catalog place name (e.g. Escario, not IT Park)."""
    key = entry.display_name.lower()
    slug_words = entry.slug.replace("_", " ")
    candidates: list[tuple[float, float, object]] = []
    for zone in zones:
        dn = (getattr(zone, "display_name", None) or "").lower()
        pn = (getattr(zone, "place_name", None) or "").lower()
        if key not in dn and key not in pn and slug_words not in dn:
            continue
        candidates.append(
            (
                _geojson_bbox_area_deg2(zone.polygon_geojson),
                haversine_km(lat, lng, zone.centroid_lat, zone.centroid_lng),
                zone,
            )
        )
    if not candidates:
        return None
    candidates.sort(key=lambda row: (row[0], row[1]))
    return candidates[0][2]


def _find_current_zone(db: Session, zones: list, *, lat: float, lng: float):
    catalog_place = _catalog_place_at_point(db, lat=lat, lng=lng)
    if catalog_place is not None:
        matched = _zone_for_catalog_place(
            zones, catalog_place, lat=lat, lng=lng
        )
        if matched is not None:
            return matched

    containing = [z for z in zones if _zone_contains_point(z.polygon_geojson, lat=lat, lng=lng)]
    if catalog_place is not None and containing:
        key = catalog_place.display_name.lower()
        filtered = [
            z
            for z in containing
            if key in (getattr(z, "display_name", None) or "").lower()
            or key in (getattr(z, "place_name", None) or "").lower()
        ]
        if filtered:
            containing = filtered
    if containing:
        if len(containing) >= 2:
            overlap_geojson = _polygon_intersection_geojson(containing)
            if overlap_geojson is not None and _zone_contains_point(overlap_geojson, lat=lat, lng=lng):
                return _synthetic_mixed_overlap_zone(containing, overlap_geojson, lat=lat, lng=lng)
        # Single zone, or overlap geometry degenerate / unavailable: pick one polygon.
        # Prefer the tightest footprint so a street-scale zone wins over a
        # broad campus/region polygon that also contains the same point.
        def sort_key(z):
            area = _geojson_bbox_area_deg2(z.polygon_geojson)
            d = haversine_km(lat, lng, z.centroid_lat, z.centroid_lng)
            return (area, d)

        containing.sort(key=sort_key)
        return containing[0]
    if catalog_place is not None:
        entry = catalog_entry_for_name(catalog_place.display_name)
        if entry is not None:
            for zone in zones:
                if entry.zone_name.lower() in (
                    getattr(zone, "display_name", None) or ""
                ).lower():
                    return zone

    catalog_near = nearest_catalog_entry(lat, lng)
    if catalog_near is not None:
        for zone in zones:
            name = catalog_near.zone_name.lower()
            if name in (getattr(zone, "display_name", None) or "").lower():
                return zone

    distances = [
        (
            haversine_km(lat, lng, zone.centroid_lat, zone.centroid_lng),
            zone,
        )
        for zone in zones
    ]
    distances.sort(key=lambda pair: pair[0])
    return distances[0][1] if distances else None


def _nearby_ranked(
    zones: list,
    *,
    lat: float,
    lng: float,
    exclude_zone_ids: set[UUID],
    limit: int,
    radius_km: float,
) -> list:
    ranked: list[tuple[float, object]] = []
    for zone in zones:
        if zone.zone_id in exclude_zone_ids:
            continue
        distance_km = haversine_km(lat, lng, zone.centroid_lat, zone.centroid_lng)
        if distance_km <= radius_km:
            ranked.append((distance_km, zone))
    ranked.sort(key=lambda pair: pair[0])
    return [z for _, z in ranked[:limit]]


def _polygon_intersection_geojson(zones: list) -> dict | None:
    """Return GeoJSON for the geometric intersection of all zone polygons."""
    try:
        from shapely.geometry import mapping  # type: ignore
        from shapely.geometry import shape  # type: ignore
        from shapely.ops import unary_union  # type: ignore
    except ImportError:
        log.debug("shapely unavailable; cannot compute zone overlap")
        return None

    geoms = []
    for z in zones:
        try:
            g = shape(z.polygon_geojson)
        except Exception:
            return None
        if g.is_empty:
            return None
        geoms.append(g)

    inter = geoms[0]
    for g in geoms[1:]:
        inter = inter.intersection(g)
    if inter.is_empty:
        return None

    if inter.geom_type == "GeometryCollection":
        polys = [x for x in inter.geoms if x.geom_type in ("Polygon", "MultiPolygon")]
        if not polys:
            return None
        inter = unary_union(polys)

    if inter.geom_type not in ("Polygon", "MultiPolygon"):
        return None

    try:
        area = float(inter.area)
    except Exception:
        area = 0.0
    if area <= 1e-20:
        return None

    try:
        return mapping(inter)
    except Exception:
        return None


def _synthetic_mixed_overlap_zone(containing: list, overlap_geojson: dict, *, lat: float, lng: float):
    """Overlay zone for pins inside two or more independent polygons simultaneously."""
    ids_sorted = sorted([z.zone_id for z in containing], key=lambda zid: str(zid))
    synthetic_id = uuid.uuid5(
        uuid.NAMESPACE_URL,
        "strollwise:zone_overlap:" + ":".join(str(zid) for zid in ids_sorted),
    )
    names = sorted({z.display_name for z in containing})
    display_name = " · ".join(names) + " overlap"

    summaries = [s for z in containing if (s := (z.summary or "").strip())]
    summary = (
        "Mixed area where " + ", ".join(names) + " meet."
        if len(names) > 1
        else (summaries[0] if summaries else None)
    )

    crowd = max(float(z.crowd_level or 0) for z in containing)
    local_pct = sum(float(z.local_presence_percent or 0) for z in containing) / len(containing)
    confidence = sum(float(z.confidence_score or 0) for z in containing) / len(containing)
    priority = max(float(z.priority_score or 0) for z in containing)

    live_rank = {
        LiveStatus.PEAK_NOW.value: 4,
        LiveStatus.BUSY_NOW.value: 3,
        LiveStatus.ACTIVE_NOW.value: 2,
        LiveStatus.CAUTION_NOW.value: 2,
        LiveStatus.QUIET_NOW.value: 1,
    }
    live_status = max(
        (z.live_status for z in containing),
        key=lambda s: live_rank.get(str(s), 0),
        default=LiveStatus.QUIET_NOW.value,
    )

    peak_labels = [z.peak_time_label for z in containing if z.peak_time_label]
    peak_time_label = peak_labels[0] if peak_labels else None

    h3_union: list[str] = []
    seen: set[str] = set()
    for z in containing:
        for idx in z.source_h3_indexes_json or []:
            if idx and idx not in seen:
                seen.add(idx)
                h3_union.append(idx)

    top_lists = [list(z.top_activities_json or []) for z in containing]
    merged_top: list[str] = []
    top_seen: set[str] = set()
    for lst in top_lists:
        for act in lst:
            if act and act not in top_seen:
                top_seen.add(act)
                merged_top.append(act)
                if len(merged_top) >= 12:
                    break
        if len(merged_top) >= 12:
            break

    centroid_lat = sum(z.centroid_lat for z in containing) / len(containing)
    centroid_lng = sum(z.centroid_lng for z in containing) / len(containing)

    return SimpleNamespace(
        zone_id=synthetic_id,
        display_name=display_name,
        behavior_type=BehaviorType.MIXED_AREA.value,
        function_type=FunctionType.EMERGING_ZONE.value,
        summary=summary,
        live_status=live_status,
        polygon_geojson=overlap_geojson,
        centroid_lat=centroid_lat,
        centroid_lng=centroid_lng,
        crowd_level=crowd,
        local_presence_percent=local_pct,
        peak_time_label=peak_time_label,
        confidence_score=confidence,
        priority_score=priority,
        source_h3_indexes_json=h3_union,
        top_activities_json=merged_top,
        updated_at=None,
        _mixed_component_zone_ids=ids_sorted,
    )


def _polygon_rings_contain_point(rings: list, *, lat: float, lng: float) -> bool:
    """True if point lies inside exterior ring and outside every hole ring."""
    if not rings or not rings[0]:
        return False
    outer = rings[0]
    if not _point_in_ring(outer, lat=lat, lng=lng):
        return False
    for hole in rings[1:]:
        if hole and _point_in_ring(hole, lat=lat, lng=lng):
            return False
    return True


def _zone_contains_point(geojson: dict, *, lat: float, lng: float) -> bool:
    if not geojson:
        return False
    geom_type = geojson.get("type")
    coords = geojson.get("coordinates", [])
    if geom_type == "Polygon":
        polygons = [coords]
    elif geom_type == "MultiPolygon":
        polygons = coords
    else:
        return False
    for polygon in polygons:
        if not polygon:
            continue
        if _polygon_rings_contain_point(polygon, lat=lat, lng=lng):
            return True
    return False


def _point_in_ring(ring: list[list[float]], *, lat: float, lng: float) -> bool:
    inside = False
    if len(ring) < 3:
        return False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        intersects = (yi > lat) != (yj > lat) and lng < (xj - xi) * (lat - yi) / (
            (yj - yi) or 1e-12
        ) + xi
        if intersects:
            inside = not inside
        j = i
    return inside


def _city_activity_label(crowd_level: float) -> str:
    if crowd_level >= 0.75:
        return "peak"
    if crowd_level >= 0.55:
        return "active"
    if crowd_level >= 0.35:
        return "steady"
    return "quiet"


def _flatten_polygon_rings(geojson: dict) -> list[list[list[float]]]:
    if not geojson:
        return []
    if geojson.get("type") == "Polygon":
        return geojson.get("coordinates", [])
    if geojson.get("type") == "MultiPolygon":
        polys = geojson.get("coordinates", [])
        flat: list[list[list[float]]] = []
        for poly in polys:
            if poly:
                flat.append(poly[0])
        return flat
    return []


def _nearby_zone_ids(repo: ZoneRepository, zone) -> list[UUID]:
    ids: list[tuple[float, UUID]] = []
    for other in repo.list_active():
        if other.zone_id == zone.zone_id:
            continue
        d = haversine_km(
            zone.centroid_lat, zone.centroid_lng, other.centroid_lat, other.centroid_lng
        )
        ids.append((d, other.zone_id))
    ids.sort(key=lambda pair: pair[0])
    return [zid for _, zid in ids[:5]]


def _why_visit(zone) -> str:
    activities = ", ".join(list(zone.top_activities_json or [])[:3]) or "mixed activity"
    return (
        f"Recent travelers reported {activities}. "
        f"Confidence score is {zone.confidence_score:.0f}/100."
    )


def _live_update(zone) -> str | None:
    return {
        "peak_now": "Very active right now — expect crowds.",
        "busy_now": "Busier than usual this hour.",
        "active_now": "A steady flow of reports in the last hour.",
        "quiet_now": "Calm right now — a good time to wander.",
        "caution_now": "Several recent safety reports. Stay alert.",
    }.get(zone.live_status)
