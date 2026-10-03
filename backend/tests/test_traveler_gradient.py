from app.utils.traveler_gradient import (
    local_ratio_from_presence_percent,
    local_ratio_from_traveler_mix,
    map_color_hex,
)


def test_local_ratio_endpoints():
    assert local_ratio_from_traveler_mix("local") == 1.0
    assert local_ratio_from_traveler_mix("international") == 0.0
    assert local_ratio_from_traveler_mix("mixed") == 0.5


def test_presence_percent_drives_ratio():
    assert local_ratio_from_presence_percent(55.0) == 0.55


def test_map_color_hex_endpoints():
    assert map_color_hex(1.0).upper() == "#22C55E"
    assert map_color_hex(0.0).upper() == "#3B82F6"


def test_mixed_interpolation_is_teal_between_endpoints():
    mid = map_color_hex(0.5).upper()
    assert mid != map_color_hex(1.0).upper()
    assert mid != map_color_hex(0.0).upper()
    assert mid == "#2FA4AA"
