from __future__ import annotations

from typing import Any, Generic, TypeVar

from pydantic import BaseModel, ConfigDict

T = TypeVar("T")


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Centroid(BaseModel):
    lat: float
    lng: float


class Paginated(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int = 1
    page_size: int = 20


class MessageResponse(BaseModel):
    message: str
    data: dict[str, Any] | None = None
