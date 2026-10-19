"""The canonical JSON form (FR-011, research R4).

RFC 8785 (JCS) restricted to content data: UTF-8, object keys sorted by UTF-16 code unit, no
insignificant whitespace, minimal string escaping, and integers only. `null` and floats are
refused, so "absent" has one representation and every number is exact. So are integers outside
±(2^53 - 1) and lone surrogates, which the strict loader refuses too.

`packages/content_models/lib/src/canonical_json.dart` implements the same form in Dart, and both
must reproduce `content/examples/canonical-vectors.json`.
"""

from __future__ import annotations

import json
import re
from typing import Any

from wassal_content.loader import SAFE_INTEGER

__all__ = ["canonical_bytes", "canonical_text"]

_SURROGATE = re.compile("[\ud800-\udfff]")


def _utf16_key(key: str) -> bytes:
    return key.encode("utf-16-be", "surrogatepass")


def _normalize(value: Any, path: str) -> Any:
    # bool is checked before int, because bool is an int subclass and is allowed as itself.
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        if _SURROGATE.search(value):
            raise ValueError(f"{path}: a lone surrogate is not allowed")
        return value
    if isinstance(value, int):
        if abs(value) > SAFE_INTEGER:
            raise ValueError(f"{path}: {value} is out of range: integers are within ±(2^53 - 1)")
        return value
    if value is None:
        raise ValueError(f"{path}: null is not allowed in canonical content")
    if isinstance(value, float):
        raise ValueError(f"{path}: a float is not allowed in canonical content")
    if isinstance(value, list | tuple):
        return [_normalize(item, f"{path}[{index}]") for index, item in enumerate(value)]
    if isinstance(value, dict):
        for key in value:
            if not isinstance(key, str):
                raise ValueError(f"{path}: object key {key!r} is not a string")
            if _SURROGATE.search(key):
                raise ValueError(f"{path}: a lone surrogate is not allowed in key {key!r}")
        return {
            key: _normalize(value[key], f"{path}.{key}") for key in sorted(value, key=_utf16_key)
        }
    raise ValueError(f"{path}: a {type(value).__name__} is not a JSON value")


def canonical_text(value: Any) -> str:
    """The canonical JSON text of `value`."""
    return json.dumps(
        _normalize(value, "$"), ensure_ascii=False, separators=(",", ":"), allow_nan=False
    )


def canonical_bytes(value: Any) -> bytes:
    """The canonical JSON of `value`, encoded as UTF-8."""
    return canonical_text(value).encode("utf-8")
