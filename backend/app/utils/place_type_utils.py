"""Maps backend function_type enums to API place_type labels."""
from __future__ import annotations

from app.models.enums import FunctionType

FUNCTION_TO_PLACE_TYPE: dict[str, str] = {
    FunctionType.FOOD_HOTSPOT.value: "food",
    FunctionType.STUDENT_AREA.value: "school",
    FunctionType.TRANSPORT_ZONE.value: "transport",
    FunctionType.COMMERCIAL_ZONE.value: "commercial",
    FunctionType.RESIDENTIAL_ZONE.value: "residential",
    FunctionType.SAFETY_CONCERN.value: "safety",
    FunctionType.TOURIST_HOTSPOT.value: "tourist",
    FunctionType.BUSY_ZONE.value: "busy",
    FunctionType.EMERGING_ZONE.value: "emerging",
    FunctionType.UNKNOWN.value: "general",
}


def place_type_from_function(function_type: str) -> str:
    return FUNCTION_TO_PLACE_TYPE.get(function_type, "general")


def dominant_place_type(function_counts: dict[str, int]) -> str:
    if not function_counts:
        return "general"
    dominant_function = max(function_counts.items(), key=lambda kv: kv[1])[0]
    return place_type_from_function(dominant_function)
