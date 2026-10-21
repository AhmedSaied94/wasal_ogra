"""Wire names of enums, as `packages/trip_engine/lib/src/wire.dart`.

The content kit's generated enums are `StrEnum`s whose values are already the wire names, and the
mirror's own enums are built the same way, so the wire name of a value is its value.
"""

from __future__ import annotations

from enum import StrEnum


def wire_name(value: StrEnum) -> str:
    """The snake_case wire name of `value`."""
    return value.value


def by_wire[E: StrEnum](values: type[E], wire: object) -> E | None:
    """The member of `values` whose wire name is `wire`, or None."""
    if not isinstance(wire, str):
        return None
    try:
        return values(wire)
    except ValueError:
        return None
