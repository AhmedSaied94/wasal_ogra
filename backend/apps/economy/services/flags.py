"""Soft anomalies: accepted, and noted as flags (FR-040, research R8).

A flag is one row per player, kind and game day, with `details.count` counting the occurrences, so
a misbehaving phone can't write millions of rows. Details hold ids and numbers, never a payload.
Flags only inform: nothing about a flagged player's play changes (leagues will read them, phase 3).
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime

from apps.economy.models import PlayerFlag
from apps.economy.services.batch import BatchState

Kind = PlayerFlag.Kind


def raise_flag(
    state: BatchState, kind: str, details: Mapping[str, int | str], *, at: datetime | None = None
) -> None:
    """Note one occurrence of `kind` on the game day of `at` (the operation's effective time, or
    the server's now). Written with the batch."""
    if kind not in Kind.values:
        raise ValueError(f"unknown flag kind {kind!r}")
    state.add_flag(kind, at or state.now, details)
