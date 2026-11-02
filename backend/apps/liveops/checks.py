"""The live-ops system checks (B10 research R5, contracts/environment.md "Retired")."""

from __future__ import annotations

import os

from django.core.checks import Warning, register

from apps.liveops.registry import RETIRED_ENV_VARIABLES


@register()
def retired_env_variables(app_configs: object = None, **kwargs: object) -> list[Warning]:
    """`liveops.W001`: a retired environment variable is still set, so the host should drop it."""
    return [
        Warning(
            f"{name} is retired: its value lives in the live settings now.",
            hint="Remove it from this host's environment file after the migrate that imported it.",
            id="liveops.W001",
            obj=name,
        )
        for name in RETIRED_ENV_VARIABLES
        if os.environ.get(name)
    ]
