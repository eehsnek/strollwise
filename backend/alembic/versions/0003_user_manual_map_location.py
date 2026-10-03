"""user manual map location

Revision ID: 0003_user_manual_map_location
Revises: 0002_user_consent_fields
Create Date: 2026-05-13
"""
from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0003_user_manual_map_location"
down_revision: Union[str, None] = "0002_user_consent_fields"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("manual_map_lat", sa.Float(), nullable=True))
    op.add_column("users", sa.Column("manual_map_lng", sa.Float(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "manual_map_lng")
    op.drop_column("users", "manual_map_lat")
