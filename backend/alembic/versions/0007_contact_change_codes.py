"""Verified email and phone changes

One table. A user editing their own email or mobile number no longer writes it
straight onto `users`: the typed value waits here until a code sent to it comes
back, and only then moves.

**Why it is staged rather than saved-and-flagged.** `users.phone` is what
`/auth/otp/verify` and `/auth/login` look an account up by, so writing an
unproven number there makes it the number the person has to log in with —
while `is_phone_verified = false` records, too late, that nobody ever proved
they could receive anything at it. One typo and the account is unreachable by
the flow the app opens on. Staging inverts that: until the code is redeemed the
old contact still signs them in, and an abandoned change costs nothing.

**Why not a `purpose` column on `otp_codes`.** The same reason
`password_reset_codes` is its own table, spelled out in its model: an OtpCode
is redeemable for a login token, and `/auth/otp/verify` resolves the account
*from the number in the request*. A code that could be either kind is a code
that can be spent on the wrong one — here, creating a second account for the
new number, or logging in as whoever already holds it.

Nothing is backfilled; there are no half-finished contact changes to carry
over. `users.email`, `users.phone` and `is_phone_verified` are untouched, so
every existing account logs in exactly as it did before.

Revision ID: 0007
Revises: 0006
Create Date: 2026-09-26
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: Union[str, None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "contact_change_codes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.String(length=16), nullable=False),
        sa.Column("channel", sa.String(length=16), nullable=False),
        sa.Column("new_value", sa.String(length=255), nullable=False),
        sa.Column("code_hash", sa.String(length=255), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("consumed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.user_id"],
            # CASCADE, like every other row hanging off an account.
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        # Named, not left to Alembic. An unnamed CHECK cannot be looked up by
        # the downgrade — the mistake 0004 shipped and had to fix.
        sa.CheckConstraint(
            "channel IN ('phone', 'email')",
            name="ck_contact_change_codes_channel",
        ),
    )
    op.create_index(
        "ix_contact_change_codes_user_id",
        "contact_change_codes",
        ["user_id"],
    )
    # The lookup both endpoints do: this user's outstanding code on this
    # channel, newest first.
    op.create_index(
        "ix_contact_change_codes_user_channel",
        "contact_change_codes",
        ["user_id", "channel", "consumed_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_contact_change_codes_user_channel",
        table_name="contact_change_codes",
    )
    op.drop_index(
        "ix_contact_change_codes_user_id",
        table_name="contact_change_codes",
    )
    op.drop_table("contact_change_codes")
