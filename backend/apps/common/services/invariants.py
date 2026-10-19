"""Data invariants the restore drill runs against a restored backup (FR-040, data-model
"Invariant check").

Each check takes a psycopg connection to the restored database and returns `(passed, detail)`.
B01 registers none, so the drill reports `invariants: {}`, which passes. B03 registers
`economy.wallet_equals_ledger` (backend §7.2).

Register from the owning app's `AppConfig.ready()`, or from a module imported there. The drill
runs as a management command, so a check in a module nothing imports would silently not run.
"""

from __future__ import annotations

import logging
from collections.abc import Callable

import psycopg

logger = logging.getLogger(__name__)

Check = Callable[[psycopg.Connection], tuple[bool, str]]

_registry: dict[str, Check] = {}


def register(name: str) -> Callable[[Check], Check]:
    """Decorator: `@register("economy.wallet_equals_ledger")`."""

    def decorator(check: Check) -> Check:
        if name in _registry:
            raise ValueError(f"invariant {name!r} is registered twice")
        _registry[name] = check
        return check

    return decorator


def registered() -> dict[str, Check]:
    return dict(_registry)


def run_all(connection: psycopg.Connection) -> dict[str, tuple[bool, str]]:
    """Every registered check's result. A check that raises counts as failed."""
    results: dict[str, tuple[bool, str]] = {}
    for name, check in _registry.items():
        try:
            results[name] = check(connection)
        except Exception as exc:  # one broken check must not hide the others
            logger.exception("invariant raised", extra={"invariant": name})
            results[name] = (False, f"raised {type(exc).__name__}")
        connection.rollback()
    return results


def unregister(name: str) -> None:
    """For tests only."""
    _registry.pop(name, None)
