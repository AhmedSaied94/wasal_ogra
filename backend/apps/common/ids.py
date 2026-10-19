"""Time-ordered UUIDv7 identifiers for every project primary key (FR-016, backend §17.1)."""

import uuid

from uuid_utils import compat


def uuid7() -> uuid.UUID:
    """A new UUIDv7 as a standard-library `uuid.UUID`."""
    return compat.uuid7()
