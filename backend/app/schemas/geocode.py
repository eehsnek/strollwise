from pydantic import BaseModel, Field


class GeocodeHit(BaseModel):
    name: str
    place_name: str
    lat: float
    lng: float
    relevance: float = Field(ge=0, le=1)
