"""The app's suggested driver names pass the server's name check (specs/012-m07-onboarding T034,
research R7, FR-013).

The Name card suggests the names of `namePool` in the app's Arabic strings. The phone can't run the
server's filter, so this test reads the app's file and runs every name through the same check as
`settings_update`, with the filter the data migration seeds. A suggestion the server refuses would
send a new player back to the Name card.
"""

from __future__ import annotations

import json

import pytest
from django.conf import settings

from apps.accounts.models import NameFilterEntry
from apps.accounts.services import names

pytestmark = pytest.mark.django_db

ARB = settings.BASE_DIR.parent / "apps" / "mobile" / "lib" / "l10n" / "app_ar.arb"
SEPARATOR = "،"  # the Arabic comma
MIN_NAMES = 20


def name_pool() -> list[str]:
    """`namePool` as the app reads it: split on the Arabic comma, trimmed, empty parts dropped."""
    pool: str = json.loads(ARB.read_text(encoding="utf-8"))["namePool"]
    return [name.strip() for name in pool.split(SEPARATOR) if name.strip()]


def test_the_pool_has_enough_distinct_names() -> None:
    pool = name_pool()
    assert len(pool) >= MIN_NAMES
    assert len(set(pool)) == len(pool)


def test_every_suggested_name_passes_the_server_check() -> None:
    blocked = list(NameFilterEntry.objects.values_list("normalized", flat=True))
    assert blocked  # the data migration's seed list

    refused: dict[str, str] = {}
    for name in name_pool():
        try:
            stored = names.validate_display_name(name, blocked)
        except names.NameRefused as error:
            refused[name] = str(error)
        else:
            # The server stores what the phone shows.
            assert stored == name
    assert refused == {}
