"""The server's fuel numbers start equal to the app's bundled tunables (B03 tasks.md T017, research
R14).

Remote Config can change the app's copy and the environment the server's, but the defaults agree,
so a fresh install and a fresh server compute the same tank. The defaults come from the settings
reader with an empty environment, not from the running settings.
"""

from __future__ import annotations

import json

from django.conf import settings

from config.env import Env

TUNABLES = settings.BASE_DIR.parent / "apps" / "mobile" / "assets" / "config" / "tunables.json"


def test_the_fuel_defaults_equal_the_app_tunables() -> None:
    tunables = json.loads(TUNABLES.read_text(encoding="utf-8"))
    defaults = Env("test", {}).economy()
    assert {
        "fuel_max": tunables["fuel_max"],
        "fuel_max_subscriber": tunables["fuel_max_subscriber"],
        "fuel_regen_minutes": tunables["fuel_regen_minutes"],
        "ads_fuel_refill_daily_cap": tunables["ads_fuel_refill_daily_cap"],
    } == {
        "fuel_max": defaults.fuel_max,
        "fuel_max_subscriber": defaults.fuel_max_subscriber,
        "fuel_regen_minutes": defaults.fuel_regen_minutes,
        "ads_fuel_refill_daily_cap": defaults.fuel_refill_daily_cap,
    }
