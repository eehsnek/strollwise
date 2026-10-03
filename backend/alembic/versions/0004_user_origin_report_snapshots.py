"""user origin fields and report analytics snapshots

Revision ID: 0004_user_origin_snapshots
Revises: 0003_user_manual_map_location
Create Date: 2026-05-15
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Union

import sqlalchemy as sa

from alembic import op

revision: str = "0004_user_origin_snapshots"
down_revision: Union[str, None] = "0003_user_manual_map_location"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("country_of_origin", sa.String(length=120), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("city_of_origin", sa.String(length=120), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("user_type", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "reports",
        sa.Column("user_type_snapshot", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "reports",
        sa.Column(
            "country_of_origin_snapshot", sa.String(length=120), nullable=True
        ),
    )
    op.add_column(
        "reports",
        sa.Column("city_of_origin_snapshot", sa.String(length=120), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("reports", "city_of_origin_snapshot")
    op.drop_column("reports", "country_of_origin_snapshot")
    op.drop_column("reports", "user_type_snapshot")
    op.drop_column("users", "user_type")
    op.drop_column("users", "city_of_origin")
    op.drop_column("users", "country_of_origin")
