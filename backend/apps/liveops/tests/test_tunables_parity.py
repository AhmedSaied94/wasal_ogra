"""One parity test for every phone key (B10 research R9, FR-008, contracts/settings.md).

Every key in the app's bundled `tunables.json` is in the registry with an equal default and a
phone-facing `applied_by`; every phone-facing registry key is in the file. B03's four-key test is
replaced by this one.
"""

from __future__ import annotations

import json

from django.conf import settings

from apps.liveops import registry

TUNABLES = settings.BASE_DIR.parent / "apps" / "mobile" / "assets" / "config" / "tunables.json"
BOTH = {"fuel_max", "fuel_max_subscriber", "fuel_regen_minutes", "ads_fuel_refill_daily_cap"}


def test_every_tunables_key_is_a_phone_setting_with_its_default() -> None:
    tunables = json.loads(TUNABLES.read_text(encoding="utf-8"))
    for key, default in tunables.items():
        spec = registry.get(key)
        assert spec.applied_by in (registry.PHONE, registry.BOTH), key
        assert spec.default == default, key


def test_every_phone_facing_setting_is_in_the_file() -> None:
    tunables = json.loads(TUNABLES.read_text(encoding="utf-8"))
    phone_facing = {
        spec.key
        for spec in registry.SPECS.values()
        if spec.applied_by in (registry.PHONE, registry.BOTH)
    }
    assert phone_facing == set(tunables)


def test_the_four_keys_the_server_also_applies() -> None:
    assert {
        spec.key for spec in registry.SPECS.values() if spec.applied_by == registry.BOTH
    } == BOTH
