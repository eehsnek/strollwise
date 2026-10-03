"""Shared tag keyword buckets used by aggregation + classification services.

Kept in a tiny module so services can import it without a circular dependency.
"""
from __future__ import annotations

FOOD_TAGS = {
    "food",
    "restaurant",
    "cafe",
    "street_food",
    "dining",
    "coffee",
    "bar",
    "bbq",
    "dessert",
    "bakery",
}
STUDENT_TAGS = {
    "school",
    "student",
    "university",
    "campus",
    "library",
    "study",
    "classroom",
}
TRANSPORT_TAGS = {
    "bus",
    "taxi",
    "jeepney",
    "transport",
    "terminal",
    "port",
    "airport",
    "ride",
    "commute",
}
COMMERCIAL_TAGS = {
    "shopping",
    "mall",
    "market",
    "office",
    "retail",
    "commercial",
    "store",
    "business",
}
RESIDENTIAL_TAGS = {
    "residential",
    "quiet",
    "home",
    "neighborhood",
    "village",
    "subdivision",
}
SAFETY_TAGS = {
    "safety",
    "theft",
    "scam",
    "crime",
    "issue",
    "danger",
    "unsafe",
}
NIGHTLIFE_TAGS = {
    "nightlife",
    "bar",
    "club",
    "karaoke",
    "party",
    "late_night",
}
