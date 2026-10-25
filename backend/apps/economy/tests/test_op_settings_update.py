"""`settings_update` (B03 tasks.md T071, research R10, FR-023)."""

from __future__ import annotations

from typing import Any

import pytest
from pytest_django import Settings

from apps.accounts.models import NameFilterEntry, Player
from apps.economy.services.batch import Outcome
from apps.economy.services.ops import profile
from apps.economy.tests.helpers import op, run

pytestmark = pytest.mark.django_db


def update(**payload: Any) -> dict[str, Any]:
    return op("settings_update", payload)


def outcome(player: Player, envelope: dict[str, Any]) -> Outcome:
    return run(player, envelope).results[0].outcome


def refused_field(player: Player, envelope: dict[str, Any]) -> str:
    result = outcome(player, envelope)
    assert result.reason == "validation_error"
    assert result.details is not None
    field: str = result.details["field"]
    return field


def test_a_name_is_stored_trimmed_and_normalized(player: Player) -> None:
    assert outcome(player, update(display_name="  الأسطى   حمادة ")).status == "accepted"
    player.refresh_from_db()
    assert player.display_name == "الأسطى حمادة"


@pytest.mark.parametrize(
    "name",
    [
        "ح",  # too short
        "ح" * 21,  # too long
        "  ح  ",  # too short once trimmed
        "123456",  # only digits
        "١٢٣٤",  # only Arabic-Indic digits
        "حمادة​",  # a zero-width space
        "حمادة‮",  # a bidi override
        "حما\x07دة",  # a control character
    ],
)
def test_a_name_that_breaks_a_rule_is_refused(player: Player, name: str) -> None:
    assert refused_field(player, update(display_name=name)) == "display_name"
    player.refresh_from_db()
    assert player.display_name == ""


def test_the_length_comes_from_the_settings(player: Player, settings: Settings) -> None:
    settings.ECONOMY_NAME_MIN_LENGTH = 4
    assert refused_field(player, update(display_name="حمد")) == "display_name"
    assert outcome(player, update(display_name="حمادة")).status == "accepted"


def test_a_name_with_a_filtered_term_is_refused_in_any_spelling(player: Player) -> None:
    NameFilterEntry.objects.create(term="حمار")
    for name in ("الحمار الكبير", "الحماااار", "حُمار", "حمــار", "ح م ا ر"):  # noqa: RUF001
        assert refused_field(player, update(display_name=name)) == "display_name", name
    assert outcome(player, update(display_name="حمادة")).status == "accepted"


def test_the_seed_list_blocks_a_staff_word(player: Player) -> None:
    assert refused_field(player, update(display_name="Admin")) == "display_name"


def test_settings_are_merged_with_known_keys_only(player: Player) -> None:
    first = update(settings={"digits": "western", "sound": False, "notif_daily": True})
    assert outcome(player, first).status == "accepted"
    assert outcome(player, update(settings={"music": False})).status == "accepted"
    player.refresh_from_db()
    assert player.settings == {
        "digits": "western",
        "sound": False,
        "notif_daily": True,
        "music": False,
    }


@pytest.mark.parametrize(
    "value",
    [
        {"theme": "dark"},  # an unknown key
        {"digits": "roman"},  # not one of the values
        {"sound": 1},  # not a boolean
        {"pre_trip_card_mode": True},
        {"notif_marketing": True},  # not a category
        ["digits"],  # not an object
    ],
)
def test_bad_settings_are_refused(player: Player, value: Any) -> None:
    assert refused_field(player, update(settings=value)) == "settings"
    player.refresh_from_db()
    assert player.settings == {}


def test_settings_over_2_kb_are_refused(player: Player, monkeypatch: pytest.MonkeyPatch) -> None:
    every = {
        "digits": "western",
        "sound": True,
        "music": True,
        "haptics": True,
        "pre_trip_card_mode": "new_only",
        "notif_daily": True,
        "notif_story": True,
        "notif_comeback": True,
        "notif_league": True,
    }
    assert outcome(player, update(settings=every)).status == "accepted"
    monkeypatch.setattr(profile, "MAX_SETTINGS_BYTES", 64)
    assert refused_field(player, update(settings={"music": False})) == "settings"


def test_a_name_and_settings_together(player: Player) -> None:
    result = outcome(player, update(display_name="حمادة", settings={"haptics": False}))
    assert result.status == "accepted"
    player.refresh_from_db()
    assert (player.display_name, player.settings) == ("حمادة", {"haptics": False})


def test_a_payload_without_either_key_is_a_validation_error(player: Player) -> None:
    assert refused_field(player, update()) == "payload"
    assert refused_field(player, update(display_name=7)) == "display_name"
