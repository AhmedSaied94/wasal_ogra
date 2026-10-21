"""The budgets hold only when nothing traces the mirror: coverage makes it about five times slower.
CI runs `tests/perf` in its own step, without coverage (contracts/ci-checks.md)."""

from __future__ import annotations

import sys

import pytest


@pytest.fixture(autouse=True)
def _untraced() -> None:
    if sys.gettrace() is not None or sys.monitoring.get_tool(sys.monitoring.COVERAGE_ID):
        pytest.skip("a tracer slows the mirror: run tests/perf without coverage")
