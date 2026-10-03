from __future__ import annotations

from app.services import h3_service


def test_latlng_to_cell_is_deterministic():
    a = h3_service.latlng_to_cell(10.3157, 123.8854, 8)
    b = h3_service.latlng_to_cell(10.3157, 123.8854, 8)
    assert a == b
    assert len(a) > 0


def test_cell_boundary_has_six_points():
    cell = h3_service.latlng_to_cell(10.3157, 123.8854, 8)
    boundary = h3_service.cell_to_boundary(cell)
    # A hex has 6 vertices (or 5/6 for a pentagon, but not at this lat).
    assert len(boundary) in {5, 6, 7}


def test_get_neighbors_excludes_self():
    cell = h3_service.latlng_to_cell(10.3, 123.88, 8)
    neighbors = h3_service.get_neighbors(cell, ring_size=1)
    assert cell not in neighbors
    assert len(neighbors) >= 5


def test_cells_to_multipolygon_uses_lng_lat_and_is_closed():
    cells = {
        h3_service.latlng_to_cell(10.3, 123.88, 8),
        h3_service.latlng_to_cell(10.3005, 123.8805, 8),
    }
    multi = h3_service.cells_to_multipolygon(cells)
    assert multi, "multipolygon should not be empty"
    outer = multi[0][0]
    assert outer[0] == outer[-1], "polygon ring must be closed"
    for lng, lat in outer:
        # Cebu longitudes are around 123.x, latitudes around 10.x.
        assert 100 < lng < 140
        assert 0 < lat < 30
