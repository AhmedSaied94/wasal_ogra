"""Keep `LiveSetting` in step with the registry after a migrate (B10 research R2).

A deploy that adds a key creates its row from the code default; a key that is back in the registry
revives its row, value kept, however it was marked; a row whose key the registry no longer has is
marked `unused` and never read. Nothing is ever deleted.
"""

from __future__ import annotations

from apps.liveops import registry


def sync_registry_rows() -> None:
    from apps.liveops.models import LiveSetting

    existing = set(LiveSetting.objects.values_list("key", flat=True))
    missing = [spec for key, spec in registry.SPECS.items() if key not in existing]
    if missing:
        LiveSetting.objects.bulk_create(
            [LiveSetting(key=spec.key, value=spec.default) for spec in missing]
        )
    # Every key in the registry is live again, including one a rollback marked `unused`: a saved
    # value must never be silently replaced by the code default (R1-5).
    LiveSetting.objects.filter(key__in=list(registry.SPECS), unused=True).update(unused=False)
    LiveSetting.objects.exclude(key__in=list(registry.SPECS)).update(unused=True)
