"""add idempotency sync fields

Revision ID: e8a1f2b3c4d5
Revises: d4cf556a873d
Create Date: 2026-05-19 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e8a1f2b3c4d5"
down_revision: Union[str, Sequence[str], None] = "d4cf556a873d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    for table in (
        "blood_pressure_records",
        "blood_sugar_records",
        "medication_logs",
    ):
        op.add_column(
            table,
            sa.Column("idempotency_key", sa.String(length=36), nullable=True),
        )
        op.add_column(
            table,
            sa.Column("created_at_local", sa.DateTime(timezone=True), nullable=True),
        )
        op.create_index(
            f"uq_{table}_idempotency_key",
            table,
            ["idempotency_key"],
            unique=True,
        )


def downgrade() -> None:
    for table in (
        "medication_logs",
        "blood_sugar_records",
        "blood_pressure_records",
    ):
        op.drop_index(f"uq_{table}_idempotency_key", table_name=table)
        op.drop_column(table, "created_at_local")
        op.drop_column(table, "idempotency_key")
