"""initial schema

Revision ID: 0001_init
Revises:
Create Date: 2026-04-23
"""
from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geometry
from sqlalchemy.dialects import postgresql

revision: str = "0001_init"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # PostGIS is required for the MultiPolygon geometry column on merged_zones.
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("display_name", sa.String(length=120), nullable=True),
        sa.Column("traveler_type", sa.String(length=32), nullable=False, server_default="mixed"),
        sa.Column("nationality", sa.String(length=8), nullable=True),
        sa.Column("age_range", sa.String(length=16), nullable=True),
        sa.Column("gender", sa.String(length=16), nullable=True),
        sa.Column("avatar_url", sa.String(length=500), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_users"),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    op.create_table(
        "reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("h3_index", sa.String(length=20), nullable=False),
        sa.Column("resolution", sa.Integer(), nullable=False, server_default="8"),
        sa.Column("latitude_raw", sa.Float(), nullable=False),
        sa.Column("longitude_raw", sa.Float(), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column(
            "tags_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("note_text", sa.String(length=1000), nullable=True),
        sa.Column("image_url", sa.String(length=500), nullable=True),
        sa.Column("source_type", sa.String(length=16), nullable=False, server_default="user"),
        sa.Column("traveler_type_snapshot", sa.String(length=32), nullable=True),
        sa.Column("visibility_status", sa.String(length=16), nullable=False, server_default="visible"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], ondelete="SET NULL", name="fk_reports_user_id_users"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_reports"),
    )
    op.create_index("ix_reports_user_id", "reports", ["user_id"])
    op.create_index("ix_reports_h3_index", "reports", ["h3_index"])
    op.create_index("ix_reports_category", "reports", ["category"])
    op.create_index("ix_reports_created_at", "reports", ["created_at"])

    op.create_table(
        "h3_cell_aggregates",
        sa.Column("h3_index", sa.String(length=20), nullable=False),
        sa.Column("resolution", sa.Integer(), nullable=False, server_default="8"),
        sa.Column("report_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("local_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("international_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("mixed_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column(
            "category_counts_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "tag_counts_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("dominant_category", sa.String(length=32), nullable=True),
        sa.Column(
            "dominant_tags_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("behavior_type", sa.String(length=32), nullable=False, server_default="mixed_area"),
        sa.Column("function_type", sa.String(length=32), nullable=False, server_default="unknown"),
        sa.Column("crowd_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column("popularity_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column("confidence_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column(
            "time_distribution_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "peak_hours_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("last_report_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("h3_index", name="pk_h3_cell_aggregates"),
    )
    op.create_index(
        "ix_h3_cell_aggregates_resolution", "h3_cell_aggregates", ["resolution"]
    )
    op.create_index(
        "ix_h3_cell_aggregates_behavior_type", "h3_cell_aggregates", ["behavior_type"]
    )
    op.create_index(
        "ix_h3_cell_aggregates_function_type", "h3_cell_aggregates", ["function_type"]
    )

    op.create_table(
        "merged_zones",
        sa.Column("zone_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("display_name", sa.String(length=160), nullable=False),
        sa.Column("slug", sa.String(length=180), nullable=False),
        sa.Column("behavior_type", sa.String(length=32), nullable=False),
        sa.Column("function_type", sa.String(length=32), nullable=False),
        sa.Column("summary", sa.String(length=600), nullable=True),
        sa.Column("live_status", sa.String(length=24), nullable=False, server_default="quiet_now"),
        sa.Column("polygon_geojson", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "polygon_geometry",
            Geometry(geometry_type="MULTIPOLYGON", srid=4326, spatial_index=False),
            nullable=True,
        ),
        sa.Column("centroid_lat", sa.Float(), nullable=False),
        sa.Column("centroid_lng", sa.Float(), nullable=False),
        sa.Column(
            "source_h3_indexes_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("crowd_level", sa.Float(), nullable=False, server_default="0"),
        sa.Column("local_presence_percent", sa.Float(), nullable=False, server_default="0"),
        sa.Column("peak_time_label", sa.String(length=40), nullable=True),
        sa.Column(
            "top_activities_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("confidence_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column("priority_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column("report_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("zone_id", name="pk_merged_zones"),
        sa.UniqueConstraint("slug", name="uq_merged_zones_slug"),
    )
    op.create_index("ix_merged_zones_slug", "merged_zones", ["slug"], unique=True)
    op.create_index("ix_merged_zones_behavior_type", "merged_zones", ["behavior_type"])
    op.create_index("ix_merged_zones_function_type", "merged_zones", ["function_type"])
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_merged_zones_polygon_geometry "
        "ON merged_zones USING GIST (polygon_geometry)"
    )

    op.create_table(
        "zone_snapshots",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("zone_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("snapshot_date", sa.Date(), nullable=False),
        sa.Column("behavior_type", sa.String(length=32), nullable=False),
        sa.Column("function_type", sa.String(length=32), nullable=False),
        sa.Column("crowd_level", sa.Float(), nullable=False, server_default="0"),
        sa.Column("local_presence_percent", sa.Float(), nullable=False, server_default="0"),
        sa.Column("confidence_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column("report_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "summary_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["zone_id"],
            ["merged_zones.zone_id"],
            ondelete="CASCADE",
            name="fk_zone_snapshots_zone_id_merged_zones",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_zone_snapshots"),
    )
    op.create_index("ix_zone_snapshots_zone_id", "zone_snapshots", ["zone_id"])
    op.create_index("ix_zone_snapshots_snapshot_date", "zone_snapshots", ["snapshot_date"])

    op.create_table(
        "saved_zones",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("zone_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], ondelete="CASCADE", name="fk_saved_zones_user_id_users"
        ),
        sa.ForeignKeyConstraint(
            ["zone_id"],
            ["merged_zones.zone_id"],
            ondelete="CASCADE",
            name="fk_saved_zones_zone_id_merged_zones",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_saved_zones"),
        sa.UniqueConstraint("user_id", "zone_id", name="uq_saved_zones_user_zone"),
    )
    op.create_index("ix_saved_zones_user_id", "saved_zones", ["user_id"])
    op.create_index("ix_saved_zones_zone_id", "saved_zones", ["zone_id"])

    op.create_table(
        "media",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("report_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("file_url", sa.String(length=600), nullable=False),
        sa.Column("mime_type", sa.String(length=80), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["report_id"], ["reports.id"], ondelete="CASCADE", name="fk_media_report_id_reports"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_media"),
    )
    op.create_index("ix_media_report_id", "media", ["report_id"])

    op.create_table(
        "audit_logs",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("actor_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("action_type", sa.String(length=64), nullable=False),
        sa.Column("entity_type", sa.String(length=64), nullable=False),
        sa.Column("entity_id", sa.String(length=64), nullable=True),
        sa.Column("payload_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["actor_user_id"],
            ["users.id"],
            ondelete="SET NULL",
            name="fk_audit_logs_actor_user_id_users",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_audit_logs"),
    )


def downgrade() -> None:
    op.drop_table("audit_logs")
    op.drop_index("ix_media_report_id", table_name="media")
    op.drop_table("media")
    op.drop_index("ix_saved_zones_zone_id", table_name="saved_zones")
    op.drop_index("ix_saved_zones_user_id", table_name="saved_zones")
    op.drop_table("saved_zones")
    op.drop_index("ix_zone_snapshots_snapshot_date", table_name="zone_snapshots")
    op.drop_index("ix_zone_snapshots_zone_id", table_name="zone_snapshots")
    op.drop_table("zone_snapshots")
    op.execute("DROP INDEX IF EXISTS ix_merged_zones_polygon_geometry")
    op.drop_index("ix_merged_zones_function_type", table_name="merged_zones")
    op.drop_index("ix_merged_zones_behavior_type", table_name="merged_zones")
    op.drop_index("ix_merged_zones_slug", table_name="merged_zones")
    op.drop_table("merged_zones")
    op.drop_index("ix_h3_cell_aggregates_function_type", table_name="h3_cell_aggregates")
    op.drop_index("ix_h3_cell_aggregates_behavior_type", table_name="h3_cell_aggregates")
    op.drop_index("ix_h3_cell_aggregates_resolution", table_name="h3_cell_aggregates")
    op.drop_table("h3_cell_aggregates")
    op.drop_index("ix_reports_created_at", table_name="reports")
    op.drop_index("ix_reports_category", table_name="reports")
    op.drop_index("ix_reports_h3_index", table_name="reports")
    op.drop_index("ix_reports_user_id", table_name="reports")
    op.drop_table("reports")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
