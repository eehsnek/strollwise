from __future__ import annotations

from app.services.place_catalog import catalog_place_at_point
from app.services.zone_catalog import CEBU_ZONE_CATALOG, cells_for_catalog_zone
from app.utils.h3_display import display_h3_rings, zone_display_rings


def test_catalog_zone_cell_counts_scale_with_radius():
    colon = next(e for e in CEBU_ZONE_CATALOG if e.zone_id == "Z006")
    mactan = next(e for e in CEBU_ZONE_CATALOG if e.zone_id == "Z005")
    assert len(cells_for_catalog_zone(colon)) < len(cells_for_catalog_zone(mactan))


def test_zone_display_rings_are_hexes_not_single_blob():
    entry = next(e for e in CEBU_ZONE_CATALOG if e.zone_id == "Z010")
    cells = cells_for_catalog_zone(entry)
    rings = zone_display_rings(None, cells)
    assert len(rings) >= 5
    assert all(len(r) >= 4 for r in rings)


def test_fuente_and_escario_pins_resolve_separately():
    assert catalog_place_at_point(lat=10.3100, lng=123.8916).slug == "z010"
    assert catalog_place_at_point(lat=10.3157, lng=123.8919).slug == "z014"
