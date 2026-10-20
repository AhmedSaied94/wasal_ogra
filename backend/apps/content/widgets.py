"""Right-to-left inputs for the Arabic text fields (FR-014). No script, so the admin CSP holds."""

from __future__ import annotations

from typing import Any

from django import forms

ARABIC = {"dir": "rtl", "lang": "ar"}


class ArabicTextInput(forms.TextInput):
    def __init__(self, attrs: dict[str, Any] | None = None) -> None:
        super().__init__({**ARABIC, "class": "vTextField", **(attrs or {})})


class ArabicTextarea(forms.Textarea):
    def __init__(self, attrs: dict[str, Any] | None = None) -> None:
        super().__init__({**ARABIC, "rows": 2, "cols": 60, **(attrs or {})})


def is_arabic_field(name: str) -> bool:
    return name.endswith(("_ar_eg", "_ar"))


def arabic_widget(name: str) -> forms.Widget:
    """Names and titles are one line. Speech, scene and request texts get a textarea."""
    return ArabicTextarea() if name.startswith("text_") else ArabicTextInput()
