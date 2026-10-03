"""zone_catalog_entries table

Revision ID: 0008_zone_catalog_entries
Revises: 0007_admin_system_settings
Create Date: 2026-05-29
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0008_zone_catalog_entries"
down_revision = "0007_admin_system_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "zone_catalog_entries",
        sa.Column("zone_id", sa.String(length=16), nullable=False),
        sa.Column("zone_name", sa.String(length=160), nullable=False),
        sa.Column("city", sa.String(length=120), nullable=False),
        sa.Column("zone_type", sa.String(length=16), nullable=False),
        sa.Column("radius_km", sa.Float(), nullable=False),
        sa.Column("center_lat", sa.Float(), nullable=False),
        sa.Column("center_lng", sa.Float(), nullable=False),
        sa.Column(
            "characteristics_json",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="[]",
            nullable=False,
        ),
        sa.Column("default_local_ratio", sa.Float(), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("zone_id"),
        sa.UniqueConstraint("zone_name"),
    )


def downgrade() -> None:
    op.drop_table("zone_catalog_entries")
