"""user visit pins for private map history

Revision ID: 0006_user_visit_pins
Revises: 0005_places_zone_link
"""
from __future__ import annotations

from collections.abc import Sequence
from typing import Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0006_user_visit_pins"
down_revision: Union[str, None] = "0005_places_zone_link"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_visit_pins",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("h3_index", sa.String(length=20), nullable=False),
        sa.Column("resolution", sa.Integer(), nullable=False, server_default="8"),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("label", sa.String(length=160), nullable=True),
        sa.Column("note", sa.String(length=280), nullable=True),
        sa.Column("source", sa.String(length=16), nullable=False, server_default="manual"),
        sa.Column("visit_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("report_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "first_visited_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "last_visited_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["report_id"], ["reports.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_user_visit_pins_user_id", "user_visit_pins", ["user_id"])
    op.create_index("ix_user_visit_pins_h3_index", "user_visit_pins", ["h3_index"])
    op.create_index(
        "ix_user_visit_pins_last_visited_at", "user_visit_pins", ["last_visited_at"]
    )
    op.create_index(
        "uq_user_visit_pins_user_h3",
        "user_visit_pins",
        ["user_id", "h3_index"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("uq_user_visit_pins_user_h3", table_name="user_visit_pins")
    op.drop_index("ix_user_visit_pins_last_visited_at", table_name="user_visit_pins")
    op.drop_index("ix_user_visit_pins_h3_index", table_name="user_visit_pins")
    op.drop_index("ix_user_visit_pins_user_id", table_name="user_visit_pins")
    op.drop_table("user_visit_pins")
