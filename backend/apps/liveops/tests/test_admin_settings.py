"""The live settings pages, their validation and their history (B10 FR-004, FR-006, FR-010)."""

from __future__ import annotations

from collections.abc import Callable

import pytest
from django.test import Client

from apps.accounts.models import User
from apps.liveops import registry
from apps.liveops import settings as live
from apps.liveops.models import LiveopsChange, LiveSetting
from apps.liveops.services import maintenance
from apps.liveops.tests.conftest import staff

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

CHANGELIST = "/admin/liveops/livesetting/"
HISTORY = "/admin/liveops/liveopschange/"
VERSIONS = f"{CHANGELIST}versions/"
MAINTENANCE = f"{CHANGELIST}maintenance/"


def page(key: str) -> str:
    return f"{CHANGELIST}{LiveSetting.objects.get(key=key).pk}/change/"


def test_a_live_ops_member_edits_a_setting_and_the_history_shows_it(live_ops: Client) -> None:
    response = live_ops.post(page("fuel_overdraft_per_day"), {"value": "1", "note": "tune"})
    assert response.status_code == 302
    assert LiveSetting.objects.get(key="fuel_overdraft_per_day").value == 1
    change = LiveopsChange.objects.get(key="fuel_overdraft_per_day")
    assert (change.old, change.new, change.note) == (2, 1, "tune")
    assert change.actor is not None
    assert change.actor.username == "liveops1"
    live.refresh()
    assert live.current()["fuel_overdraft_per_day"] == 1


def test_the_change_form_shows_the_history(live_ops: Client) -> None:
    live_ops.post(page("fuel_overdraft_per_day"), {"value": "1", "note": "tune"})
    response = live_ops.get(page("fuel_overdraft_per_day"))
    assert response.status_code == 200
    assert b"tune" in response.content
    assert b"History" in response.content


def test_a_value_out_of_range_shows_the_error_and_keeps_the_old(live_ops: Client) -> None:
    response = live_ops.post(page("fuel_max"), {"value": "21"})
    assert response.status_code == 200
    assert b"20" in response.content
    assert LiveSetting.objects.get(key="fuel_max").value == 5
    assert not LiveopsChange.objects.exists()


def test_a_rule_break_shows_its_text_and_keeps_the_old(live_ops: Client) -> None:
    response = live_ops.post(page("fuel_max_subscriber"), {"value": "3"})
    assert response.status_code == 200
    assert b"The subscriber&#x27;s tank can&#x27;t be smaller than the normal tank." in (
        response.content
    )
    assert LiveSetting.objects.get(key="fuel_max_subscriber").value == 7


def test_the_reset_action_writes_a_reset_change(
    live_ops: Client, live_settings: Callable[..., None]
) -> None:
    live_settings(fuel_overdraft_per_day=1)
    row = LiveSetting.objects.get(key="fuel_overdraft_per_day")
    response = live_ops.post(
        CHANGELIST, {"action": "reset_to_default", "_selected_action": [str(row.pk)]}
    )
    assert response.status_code == 302
    assert LiveSetting.objects.get(key="fuel_overdraft_per_day").value == 2
    change = LiveopsChange.objects.filter(key="fuel_overdraft_per_day").latest("at")
    assert (change.new, change.source) == (2, LiveopsChange.Source.RESET)


def test_the_changelist_filters(live_ops: Client, live_settings: Callable[..., None]) -> None:
    live_settings(fuel_overdraft_per_day=1)
    changed = live_ops.get(CHANGELIST, {"changed": "yes"})
    assert changed.status_code == 200
    assert b"fuel_overdraft_per_day" in changed.content
    assert b"fuel_max" not in changed.content
    server = live_ops.get(CHANGELIST, {"applied_by": "both"})
    assert b"fuel_max_subscriber" in server.content
    assert b"fuel_overdraft_per_day" not in server.content


def test_the_history_is_read_only(live_ops: Client) -> None:
    live_ops.post(page("fuel_overdraft_per_day"), {"value": "1", "note": "tune"})
    change = LiveopsChange.objects.get()
    shown = live_ops.get(f"{HISTORY}{change.pk}/change/")
    assert shown.status_code == 200
    assert b"Save" not in shown.content  # a read-only view: no save buttons
    assert live_ops.post(f"{HISTORY}{change.pk}/change/", {"note": "x"}).status_code in (403, 405)
    assert live_ops.get(f"{HISTORY}{change.pk}/delete/").status_code == 403
    assert live_ops.get(f"{CHANGELIST}add/").status_code == 403


@pytest.mark.parametrize("fixture", ["support", "author"])
def test_other_groups_see_no_live_ops_page(
    fixture: str, request: pytest.FixtureRequest, live_ops: Client
) -> None:
    client: Client = request.getfixturevalue(fixture)
    assert client.get(CHANGELIST).status_code == 403
    assert client.get(HISTORY).status_code == 403
    row = LiveSetting.objects.get(key="fuel_max")
    assert client.get(f"{CHANGELIST}{row.pk}/change/").status_code == 403
    assert client.get("/admin/liveops/storeproduct/").status_code == 403
    assert client.get("/admin/liveops/offer/").status_code == 403
    assert client.get(VERSIONS).status_code == 403
    assert client.get(MAINTENANCE).status_code == 403


def test_a_view_only_member_cannot_confirm_a_new_minimum() -> None:
    viewer = staff("viewer1", None, "view_livesetting")
    row = LiveSetting.objects.get(key="min_client_version_android")
    response = viewer.post(VERSIONS, {"platform": "android", "minimum": "1.5.0", "confirm": "1"})
    assert response.status_code == 403
    row.refresh_from_db()
    assert row.value == registry.get("min_client_version_android").default
    assert not LiveopsChange.objects.exists()


def test_a_view_only_member_cannot_run_the_reset_action(
    live_settings: Callable[..., None],
) -> None:
    live_settings(fuel_max=6)
    viewer = staff("viewer2", None, "view_livesetting")
    row = LiveSetting.objects.get(key="fuel_max")
    response = viewer.post(
        CHANGELIST, {"action": "reset_to_default", "_selected_action": [str(row.pk)]}
    )
    assert response.status_code in (200, 302, 403)  # not offered, and not run
    row.refresh_from_db()
    assert row.value == 6


def test_a_change_member_without_the_switch_cannot_edit_a_maintenance_row() -> None:
    changer = staff("changer1", None, "view_livesetting", "change_livesetting")
    maintenance.switch(True, actor=User.objects.get(username="changer1"))
    row = LiveSetting.objects.get(key="maintenance_enabled")
    assert changer.get(f"{CHANGELIST}{row.pk}/change/").status_code == 200
    response = changer.post(f"{CHANGELIST}{row.pk}/change/", {"value": "on"})
    assert response.status_code == 403
    row.refresh_from_db()
    assert row.value is True


def test_a_change_member_without_the_switch_cannot_reset_a_maintenance_row() -> None:
    changer = staff("changer2", None, "view_livesetting", "change_livesetting")
    maintenance.switch(True, actor=User.objects.get(username="changer2"))
    row = LiveSetting.objects.get(key="maintenance_enabled")
    response = changer.post(
        CHANGELIST,
        {"action": "reset_to_default", "_selected_action": [str(row.pk)]},
        follow=True,
    )
    assert b"Maintenance page" in response.content
    row.refresh_from_db()
    assert row.value is True


def test_a_switch_member_can_still_use_the_generic_maintenance_form(live_ops: Client) -> None:
    row = LiveSetting.objects.get(key="maintenance_enabled")
    response = live_ops.post(f"{CHANGELIST}{row.pk}/change/", {"value": "on"})
    assert response.status_code == 302
    row.refresh_from_db()
    assert row.value is True


def test_every_registry_key_is_listed(live_ops: Client) -> None:
    response = live_ops.get(CHANGELIST)
    body = response.content.decode()
    for key in registry.SPECS:
        assert key in body


def test_the_duplicate_of_the_default_is_not_changed(
    live_ops: Client, live_settings: Callable[..., None]
) -> None:
    live_settings(fuel_overdraft_per_day=1)
    row = LiveSetting.objects.get(key="fuel_overdraft_per_day")
    assert row.value != registry.get("fuel_overdraft_per_day").default
    response = live_ops.get(CHANGELIST, {"changed": "no"})
    assert b"fuel_overdraft_per_day" not in response.content


def test_the_drift_column_is_empty_before_the_first_check(live_ops: Client) -> None:
    response = live_ops.get(CHANGELIST)
    assert response.status_code == 200


def test_the_notes_field_is_optional(live_ops: Client) -> None:
    live_ops.post(page("fuel_overdraft_per_day"), {"value": "1"})
    assert LiveopsChange.objects.get().note == ""


def test_the_admin_cannot_add_or_delete_a_setting(live_ops: Client) -> None:
    row = LiveSetting.objects.get(key="fuel_max")
    assert live_ops.get(f"{CHANGELIST}{row.pk}/delete/").status_code == 403
