from __future__ import annotations

from app.services import h3_service
from app.utils.h3_display import close_ring, display_h3_rings


def test_close_ring_closes_open_ring():
    ring = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0]]
    closed = close_ring(ring)
    assert closed[0] == closed[-1]
    assert len(closed) == 4


def test_display_h3_rings_returns_hex_outlines():
    idx = h3_service.latlng_to_cell(10.3370, 123.9025, 8)
    rings = display_h3_rings([idx])
    assert rings
    assert len(rings[0]) >= 4
    assert rings[0][0][0] == rings[0][-1][0]
    assert rings[0][0][1] == rings[0][-1][1]


def test_display_h3_rings_empty_for_no_indexes():
    assert display_h3_rings([]) == []
    assert display_h3_rings(None) == []
