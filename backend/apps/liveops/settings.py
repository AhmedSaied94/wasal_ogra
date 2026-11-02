"""The live settings snapshot every process keeps (B10 research R3, settings.md "Reading").

`current()` returns an immutable mapping of key to typed value. Each process re-reads the table when
its snapshot is older than `LIVEOPS_REFRESH_SECONDS`, so a change applies within a minute without a
restart; a failed read keeps the last snapshot. One snapshot per batch or request, never one per
operation.
"""

from __future__ import annotations

import logging
from collections.abc import Callable, Iterator, Mapping
from types import MappingProxyType
from typing import Any

from django.conf import settings as django_settings
from django.utils import timezone

from apps.liveops import registry

logger = logging.getLogger("apps.liveops")


class Snapshot(Mapping[str, Any]):
    """An immutable mapping of registry key to typed value. An unknown key raises `KeyError`."""

    __slots__ = ("_values",)

    def __init__(self, values: Mapping[str, Any]) -> None:
        self._values = MappingProxyType(dict(values))

    def __getitem__(self, key: str) -> Any:
        if key not in registry.SPECS:
            raise KeyError(key)
        return self._values[key]

    def __iter__(self) -> Iterator[str]:
        return iter(self._values)

    def __len__(self) -> int:
        return len(self._values)

    def __repr__(self) -> str:
        return f"Snapshot({len(self._values)} keys)"


class Cache[T]:
    """One process's snapshot and when it was loaded (settings, products, offers)."""

    def __init__(self, load: Callable[[], T], name: str) -> None:
        self._load = load
        self._name = name
        self._snapshot: T | None = None
        self._loaded_at: Any = None

    def current(self) -> T:
        if self._snapshot is None or self._stale():
            return self.refresh()
        return self._snapshot

    def refresh(self) -> T:
        try:
            snapshot = self._load()
        except Exception:
            if self._snapshot is None:
                raise
            logger.warning("liveops_snapshot_stale", extra={"snapshot": self._name})
            return self._snapshot
        self._snapshot = snapshot
        self._loaded_at = timezone.now()
        return snapshot

    def reset(self) -> None:
        self._snapshot = None
        self._loaded_at = None

    def _stale(self) -> bool:
        if self._snapshot is None or self._loaded_at is None:
            return True
        age = (timezone.now() - self._loaded_at).total_seconds()
        return bool(age >= django_settings.LIVEOPS_REFRESH_SECONDS)


def _load_settings() -> Snapshot:
    from apps.liveops.models import LiveSetting

    values = registry.defaults()
    rows = LiveSetting.objects.filter(unused=False).values_list("key", "value")
    for key, raw in rows:
        spec = registry.SPECS.get(key)
        if spec is None:
            continue
        try:
            values[key] = registry.typed(spec, registry.validate(spec, raw))
        except ValueError:
            logger.warning("liveops_invalid_value", extra={"key": key})
    return Snapshot(values)


def _load_products() -> tuple[Any, ...]:
    from apps.liveops.models import StoreProduct

    return tuple(StoreProduct.objects.all().order_by("display_order", "product_id"))


def _load_offers() -> tuple[Any, ...]:
    from apps.liveops.models import Offer

    return tuple(Offer.objects.select_related("product").order_by("-priority", "starts_at"))


_SETTINGS: Cache[Snapshot] = Cache(_load_settings, "settings")
_PRODUCTS: Cache[tuple[Any, ...]] = Cache(_load_products, "catalog")
_OFFERS: Cache[tuple[Any, ...]] = Cache(_load_offers, "offers")


def current() -> Snapshot:
    """The settings, reloaded if the snapshot is older than `LIVEOPS_REFRESH_SECONDS`."""
    return _SETTINGS.current()


def refresh() -> Snapshot:
    """Reload now. Used after a save and by the `live_settings` test fixture."""
    return _SETTINGS.refresh()


def products() -> tuple[Any, ...]:
    """The catalog snapshot: every product row, refreshed like the settings (research R12)."""
    return _PRODUCTS.current()


def refresh_products() -> tuple[Any, ...]:
    return _PRODUCTS.refresh()


def offers() -> tuple[Any, ...]:
    """The offers snapshot, with each offer's product loaded (research R12)."""
    return _OFFERS.current()


def refresh_offers() -> tuple[Any, ...]:
    return _OFFERS.refresh()


def reset() -> None:
    """Forget every snapshot (tests). The next read goes to the tables."""
    for cache in (_SETTINGS, _PRODUCTS, _OFFERS):
        cache.reset()
