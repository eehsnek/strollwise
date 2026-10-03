from __future__ import annotations

from collections.abc import Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.h3_cell_aggregate import H3CellAggregate


class H3Repository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, h3_index: str) -> H3CellAggregate | None:
        return self.db.get(H3CellAggregate, h3_index)

    def upsert(self, cell: H3CellAggregate) -> H3CellAggregate:
        self.db.merge(cell)
        self.db.flush()
        return cell

    def list_all_active(self) -> list[H3CellAggregate]:
        stmt = select(H3CellAggregate).where(H3CellAggregate.report_count > 0)
        return list(self.db.execute(stmt).scalars())

    def list_by_indexes(self, h3_indexes: Iterable[str]) -> list[H3CellAggregate]:
        idxs = list(h3_indexes)
        if not idxs:
            return []
        stmt = select(H3CellAggregate).where(H3CellAggregate.h3_index.in_(idxs))
        return list(self.db.execute(stmt).scalars())

    def list_active_in_bbox(
        self,
        min_lat: float,
        min_lng: float,
        max_lat: float,
        max_lng: float,
        *,
        limit: int = 400,
    ) -> list[H3CellAggregate]:
        """Active cells whose centroid falls in the viewport (Python filter)."""
        cells = self.list_all_active()
        in_box: list[H3CellAggregate] = []
        from app.services import h3_service

        for cell in cells:
            lat, lng = h3_service.cell_centroid(cell.h3_index)
            if min_lat <= lat <= max_lat and min_lng <= lng <= max_lng:
                in_box.append(cell)
            if len(in_box) >= limit:
                break
        return in_box
