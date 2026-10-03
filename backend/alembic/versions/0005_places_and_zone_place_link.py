"""places table and zone/cell place links

Revision ID: 0005_places_zone_link
Revises: 0004_user_origin_snapshots
Create Date: 2026-05-17
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005_places_zone_link"
down_revision: Union[str, None] = "0004_user_origin_snapshots"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "places",
        sa.Column("place_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("slug", sa.String(length=80), nullable=False),
        sa.Column("display_name", sa.String(length=160), nullable=False),
        sa.Column("place_type", sa.String(length=32), nullable=False, server_default="general"),
        sa.Column("source", sa.String(length=16), nullable=False, server_default="catalog"),
        sa.Column("polygon_geojson", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "polygon_geometry",
            sa.Text(),
            nullable=True,
        ),
        sa.Column("centroid_lat", sa.Float(), nullable=False, server_default="0"),
        sa.Column("centroid_lng", sa.Float(), nullable=False, server_default="0"),
        sa.Column(
            "source_h3_indexes_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default="[]",
        ),
        sa.Column("report_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("confidence_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("place_id", name="pk_places"),
        sa.UniqueConstraint("slug", name="uq_places_slug"),
    )
    op.create_index("ix_places_place_type", "places", ["place_type"])
    op.create_index("ix_places_slug", "places", ["slug"])

    op.add_column(
        "h3_cell_aggregates",
        sa.Column("place_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_index("ix_h3_cell_aggregates_place_id", "h3_cell_aggregates", ["place_id"])
    op.create_foreign_key(
        "fk_h3_cell_aggregates_place_id",
        "h3_cell_aggregates",
        "places",
        ["place_id"],
        ["place_id"],
        ondelete="SET NULL",
    )

    op.add_column(
        "merged_zones",
        sa.Column("place_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "merged_zones",
        sa.Column("traveler_mix", sa.String(length=16), nullable=True),
    )
    op.create_index("ix_merged_zones_place_id", "merged_zones", ["place_id"], unique=True)
    op.create_foreign_key(
        "fk_merged_zones_place_id",
        "merged_zones",
        "places",
        ["place_id"],
        ["place_id"],
        ondelete="SET NULL",
    )
    op.alter_column("merged_zones", "function_type", existing_type=sa.String(32), nullable=True)


def downgrade() -> None:
    op.alter_column("merged_zones", "function_type", existing_type=sa.String(32), nullable=False)
    op.drop_constraint("fk_merged_zones_place_id", "merged_zones", type_="foreignkey")
    op.drop_index("ix_merged_zones_place_id", table_name="merged_zones")
    op.drop_column("merged_zones", "traveler_mix")
    op.drop_column("merged_zones", "place_id")

    op.drop_constraint("fk_h3_cell_aggregates_place_id", "h3_cell_aggregates", type_="foreignkey")
    op.drop_index("ix_h3_cell_aggregates_place_id", table_name="h3_cell_aggregates")
    op.drop_column("h3_cell_aggregates", "place_id")

    op.drop_index("ix_places_slug", table_name="places")
    op.drop_index("ix_places_place_type", table_name="places")
    op.drop_table("places")
