"""p0 launch hardening

Revision ID: a1b2c3d4e5f6
Revises: f1a2b3c4d5e6
Create Date: 2026-06-04 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, Sequence[str], None] = "f1a2b3c4d5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    is_sqlite = bind.dialect.name == "sqlite"

    op.add_column("medication_logs", sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("medication_logs", sa.Column("cancelled_by_user_id", sa.Integer(), nullable=True))
    op.create_index(
        "ix_medication_logs_cancelled_by_user_id",
        "medication_logs",
        ["cancelled_by_user_id"],
        unique=False,
    )
    if not is_sqlite:
        op.create_foreign_key(
            "fk_medication_logs_cancelled_by_user_id_users",
            "medication_logs",
            "users",
            ["cancelled_by_user_id"],
            ["id"],
        )

    for table in ("blood_pressure_records", "blood_sugar_records"):
        op.add_column(
            table,
            sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        )
        op.add_column(table, sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True))
        op.add_column(table, sa.Column("deleted_by_user_id", sa.Integer(), nullable=True))
        op.create_index(
            f"ix_{table}_deleted_by_user_id",
            table,
            ["deleted_by_user_id"],
            unique=False,
        )
        if not is_sqlite:
            op.create_foreign_key(
                f"fk_{table}_deleted_by_user_id_users",
                table,
                "users",
                ["deleted_by_user_id"],
                ["id"],
            )

    op.create_index(
        "uq_subscription_events_revenuecat_event_id",
        "subscription_events",
        ["revenuecat_event_id"],
        unique=True,
        postgresql_where=sa.text("revenuecat_event_id IS NOT NULL"),
        sqlite_where=sa.text("revenuecat_event_id IS NOT NULL"),
    )


def downgrade() -> None:
    bind = op.get_bind()
    is_sqlite = bind.dialect.name == "sqlite"

    op.drop_index(
        "uq_subscription_events_revenuecat_event_id",
        table_name="subscription_events",
    )
    for table in ("blood_sugar_records", "blood_pressure_records"):
        if not is_sqlite:
            op.drop_constraint(
                f"fk_{table}_deleted_by_user_id_users",
                table,
                type_="foreignkey",
            )
        op.drop_index(f"ix_{table}_deleted_by_user_id", table_name=table)
        op.drop_column(table, "deleted_by_user_id")
        op.drop_column(table, "deleted_at")
        op.drop_column(table, "is_deleted")

    if not is_sqlite:
        op.drop_constraint(
            "fk_medication_logs_cancelled_by_user_id_users",
            "medication_logs",
            type_="foreignkey",
        )
    op.drop_index("ix_medication_logs_cancelled_by_user_id", table_name="medication_logs")
    op.drop_column("medication_logs", "cancelled_by_user_id")
    op.drop_column("medication_logs", "cancelled_at")
