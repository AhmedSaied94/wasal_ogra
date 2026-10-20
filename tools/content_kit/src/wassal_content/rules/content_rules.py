"""Stage 3, content rules: currencies and player-visible text (V-M1, V-X1, V-X2; research R14).

Every `LocalizedText` value is trimmed and holds no digit of any script, so the player's digit
setting applies to every number (constitution X). Numbers go through placeholders, and each kind
of text allows only its own: speech lines `{amount}` and `{station}`, task text `{target}`, and
everything else none.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterator, Mapping
from typing import Any

from wassal_content.findings import Finding
from wassal_content.rules.references import price_entity
from wassal_content.schemas import IDENTIFIER_FIELDS, PACK_ARRAYS

__all__ = ["JENEHAT_KINDS", "content_rule_findings"]

STAGE = "content_rules"
JENEHAT_KINDS = frozenset({"item", "vehicle", "chapter"})
_LOCALES = ("ar-EG", "ar")
_PLACEHOLDER = re.compile(r"\{([^{}]*)\}")
_SPEECH = frozenset({"amount", "station"})
_TASK = frozenset({"target"})
_NONE: frozenset[str] = frozenset()


def _error(code: str, entity: tuple[str, str], path: str, message: str) -> Finding:
    return Finding(
        path=path, code=code, message=message, stage=STAGE, entity=entity[0], id=entity[1]
    )


def _currencies(pack: Mapping[str, Any]) -> Iterator[Finding]:
    for price in pack["catalog"]["prices"]:
        expected = "JENEHAT" if price["sku_kind"] in JENEHAT_KINDS else "BONAT"
        if price["currency"] != expected:
            yield _error(
                "V-M1",
                price_entity(price["sku_kind"], price["sku_id"]),
                "$.currency",
                f"a {price['sku_kind']} is priced in {expected}",
            )


def _texts(value: Any, path: str) -> Iterator[tuple[str, str]]:
    """Every (path, text) of the `LocalizedText` objects under `value`."""
    if isinstance(value, dict):
        if "ar-EG" in value:
            for locale in _LOCALES:
                if locale in value:
                    yield f"{path}.{locale}", value[locale]
            return
        for key, child in value.items():
            yield from _texts(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _texts(child, f"{path}[{index}]")


def _allowed(part: str, path: str) -> frozenset[str]:
    if part == "speech_pool":
        return _SPEECH
    if part == "task" and path.startswith("$.text."):
        return _TASK
    return _NONE


def _text_findings(
    text: str, allowed: frozenset[str], entity: tuple[str, str], path: str
) -> Iterator[Finding]:
    if text != text.strip():
        yield _error("V-X1", entity, path, "the text has leading or trailing whitespace")
    digits = sorted({char for char in text if unicodedata.category(char) == "Nd"})
    if digits:
        yield _error(
            "V-X1",
            entity,
            path,
            f"the text contains the digits {''.join(digits)!r}: numbers go through placeholders",
        )
    if "{" in _PLACEHOLDER.sub("", text) or "}" in _PLACEHOLDER.sub("", text):
        yield _error("V-X2", entity, path, "the text has an unbalanced brace")
    for name in _PLACEHOLDER.findall(text):
        if name not in allowed:
            accepted = ", ".join(f"{{{n}}}" for n in sorted(allowed)) or "none"
            yield _error(
                "V-X2",
                entity,
                path,
                f"placeholder {{{name}}} isn't allowed here (accepted: {accepted})",
            )


def content_rule_findings(pack: Mapping[str, Any]) -> list[Finding]:
    """Every content-rule finding of a pack that passed the schema stage."""
    findings = list(_currencies(pack))
    for array, part in PACK_ARRAYS.items():
        field = IDENTIFIER_FIELDS[part]
        for element in pack[array]:
            entity = (part, str(element[field]))
            for path, text in _texts(element, "$"):
                findings.extend(_text_findings(text, _allowed(part, path), entity, path))
    return findings
