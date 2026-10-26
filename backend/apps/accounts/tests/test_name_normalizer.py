"""The name normalizer (B03 tasks.md T072, research R10).

One function folds names and filter terms alike, so a term blocks its common spellings and the
admin shows staff exactly what is matched.
"""

from __future__ import annotations

import pytest

from apps.accounts.models import NameFilterEntry
from apps.accounts.services import names


@pytest.mark.parametrize(
    ("text", "folded"),
    [
        ("أحمد", "احمد"),
        ("إسلام", "اسلام"),
        ("آمال", "امال"),
        ("مصطفى", "مصطفي"),  # alef maqsura to ya
        ("فاطمة", "فاطمه"),
        ("مُحَمَّد", "محمد"),  # diacritics
        ("محــمد", "محمد"),  # tatweel
        ("حماااادة", "حماده"),  # repeated letters collapsed
        ("HaMaDa", "hamada"),  # Latin lowercased
        ("7mar", "حmar"),  # a look-alike digit
        ("3ali 2", "عaliء"),
        ("ا ل ح م ا ر", "الحمار"),  # noqa: RUF001 - spaces dropped
        ("ﻫﻼ", "هلا"),
    ],
)
def test_normalize(text: str, folded: str) -> None:
    assert names.normalize(text) == folded


def test_arabic_indic_digits_stand_for_the_same_letters() -> None:
    assert names.normalize("٧mar") == names.normalize("7mar")  # noqa: RUF001


def test_clean_display_name_trims_and_collapses_spaces() -> None:
    assert names.clean_display_name("  أبو \t  علي  ") == "أبو علي"


@pytest.mark.django_db
def test_an_entry_stores_its_normalized_form() -> None:
    entry = NameFilterEntry.objects.create(term="الحمــار")
    assert entry.normalized == names.normalize("الحمــار") == "الحمار"


@pytest.mark.django_db
def test_a_seed_entry_blocks_its_spelling_variants() -> None:
    blocked = list(NameFilterEntry.objects.values_list("normalized", flat=True))
    assert blocked  # the data migration's seed list
    for name in ("ADMIN", "Adminnn", "the admin"):
        with pytest.raises(names.NameRefused, match="filtered"):
            names.validate_display_name(name, blocked)
    assert names.validate_display_name("حمادة", blocked) == "حمادة"


@pytest.mark.parametrize(
    ("name", "reason"),
    [("ح", "length"), ("حمادة‏", "characters"), ("٠١٢ ٣٤", "digits")],
)
def test_validate_display_name_names_the_rule(name: str, reason: str) -> None:
    with pytest.raises(names.NameRefused, match=reason):
        names.validate_display_name(name, [])
