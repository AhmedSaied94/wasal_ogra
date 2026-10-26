"""Display names: the rules of `settings_update` and the name filter (B03 research R10, FR-023).

`normalize` is the one spelling-folding function. The name check runs it on the name, and
`NameFilterEntry.save` runs it on each term, so a term blocks its common spelling variants and the
admin shows staff exactly what is matched.
"""

from __future__ import annotations

import re
import unicodedata

from django.conf import settings

# Folded to a bare alef, alef maqsura to ya, ta marbuta to ha (research R10). The Arabic letters
# are the point of the table, so ruff's look-alike warning is off for it.
_LETTERS = str.maketrans(
    {
        "أ": "ا",  # noqa: RUF001 - alef with hamza above
        "إ": "ا",  # noqa: RUF001 - alef with hamza below
        "آ": "ا",  # noqa: RUF001 - alef with madda
        "ٱ": "ا",  # noqa: RUF001 - alef wasla
        "ى": "ي",  # alef maqsura -> ya
        "ة": "ه",  # noqa: RUF001 - ta marbuta -> ha
    }
)
# Arabic-Indic and Eastern Arabic-Indic digits, then the digits that stand for Arabic letters in
# common Latin-script spellings (3 for ain, 7 for ha, ...).
_DIGITS = str.maketrans(
    {
        **{chr(0x0660 + n): str(n) for n in range(10)},
        **{chr(0x06F0 + n): str(n) for n in range(10)},
    }
)
_LOOK_ALIKES = str.maketrans(
    {
        "2": "ء",  # hamza
        "3": "ع",  # ain
        "5": "خ",  # kha
        "6": "ط",  # ta (emphatic)
        "7": "ح",  # ha
        "8": "غ",  # ghain
        "9": "ق",  # qaf
    }
)
_DIACRITICS = re.compile("[ً-ٰٟـ]")  # harakat, superscript alef, tatweel
_REPEATS = re.compile(r"(.)\1+")
# Control, bidi and zero-width characters a name may not hold.
_INVISIBLE = re.compile("[​-‏‪-‮⁦-⁩﻿؜᠎⁠]")
_SPACES = re.compile(r"\s+")


class NameRefused(ValueError):
    """The name breaks a rule. The reason is a code, never the name."""


def normalize(text: str) -> str:
    """The form names and filter terms are compared in: NFKC, Latin lowercased, Arabic letter
    variants folded, diacritics and tatweel removed, look-alike digits mapped to the letters they
    stand for, anything but letters dropped, and repeated letters collapsed."""
    folded = unicodedata.normalize("NFKC", text).lower()
    folded = _DIACRITICS.sub("", folded.translate(_LETTERS).translate(_DIGITS))
    folded = folded.translate(_LOOK_ALIKES)
    letters = "".join(ch for ch in folded if ch.isalpha())
    return _REPEATS.sub(r"\1", letters)


def clean_display_name(text: str) -> str:
    """The name as stored: NFKC, trimmed, inner whitespace collapsed to one space."""
    return _SPACES.sub(" ", unicodedata.normalize("NFKC", text)).strip()


def validate_display_name(text: str, blocked: list[str]) -> str:
    """The cleaned name, or `NameRefused`. `blocked` holds the filter's normalized terms."""
    name = clean_display_name(text)
    if not settings.ECONOMY_NAME_MIN_LENGTH <= len(name) <= settings.ECONOMY_NAME_MAX_LENGTH:
        raise NameRefused("length")
    if _INVISIBLE.search(name) or any(
        unicodedata.category(ch) in ("Cc", "Cf", "Cs", "Co") for ch in name
    ):
        raise NameRefused("characters")
    if name.replace(" ", "").isdigit():
        raise NameRefused("digits")
    folded = normalize(name)
    if any(term and term in folded for term in blocked):
        raise NameRefused("filtered")
    return name
