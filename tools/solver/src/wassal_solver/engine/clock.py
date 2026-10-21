"""The logic clock's step (RULES.md §1.4), shared by the rules, the params' bounds and the log.

Mirrors `packages/trip_engine/lib/src/clock.dart`.
"""

from __future__ import annotations

STEP_MS = 33
"""One logic step, in milliseconds."""

MS_PER_SECOND = 1000
"""Authored times are in seconds, the clock in milliseconds."""
