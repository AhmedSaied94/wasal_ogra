"""The strict JSON loader for content (research R2).

Every pack and every `content/source` file goes through here before any schema runs. JSON Schema's
`integer` accepts `1.0`, and FR-003 doesn't, so the loader refuses any number with a fraction or an
exponent, the non-standard constants (`NaN`, `Infinity`), duplicate keys at any depth, invalid
UTF-8 and a byte-order mark. Each refusal names its line and column.

Imports are untrusted, so the loader also refuses what Dart and Python could read differently, or
what would crash a recursive reader later: integers outside I-JSON's safe range (RFC 7493,
±(2^53 - 1)), strings with a lone surrogate, and nesting deeper than `MAX_DEPTH` (content nests
about 8 levels).

The fast path is the C parser with refusing hooks. Only when a hook fires does a small pure-Python
scan run to find the first offending token, because the hooks don't see positions. Nesting is
checked first, so that scan never recurses deeply itself.
"""

from __future__ import annotations

import json
import json.decoder
import re
from collections.abc import Callable
from pathlib import Path
from typing import Any, NoReturn

__all__ = ["MAX_DEPTH", "SAFE_INTEGER", "ContentLoadError", "load_json_bytes", "load_json_file"]

MAX_DEPTH = 32
SAFE_INTEGER = 2**53 - 1

_BOM = b"\xef\xbb\xbf"
_WHITESPACE = re.compile(r"[ \t\n\r]*")
_NUMBER = re.compile(r"-?(?:0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?")
_CONSTANTS = ("NaN", "Infinity", "-Infinity")
_SAFE_DIGITS = len(str(SAFE_INTEGER))
_SURROGATE = re.compile("[\ud800-\udfff]")
# A JSON string, or one bracket. Strings are matched whole so that brackets inside them don't count.
_TOKEN = re.compile(r'"[^"\\]*(?:\\.[^"\\]*)*"|[\[\]{}]')
# The standard library's string scanner (the same one json.loads uses); typeshed omits it.
scanstring: Callable[[str, int, bool], tuple[str, int]] = json.decoder.scanstring  # type: ignore[attr-defined]


class ContentLoadError(ValueError):
    """A document that isn't strict JSON. `line` and `column` are 1-based."""

    def __init__(self, message: str, *, line: int, column: int) -> None:
        super().__init__(f"line {line}, column {column}: {message}")
        self.message = message
        self.line = line
        self.column = column


class _Refused(Exception):
    """Raised by the fast path's hooks. The slow scan then locates the problem."""


def _refuse(_: str) -> Any:
    raise _Refused


def _in_range(token: str) -> bool:
    # The length check comes first: int() of thousands of digits is slow, and refused past 4300.
    return len(token.lstrip("-")) <= _SAFE_DIGITS and abs(int(token)) <= SAFE_INTEGER


def _integer(token: str) -> int:
    if not _in_range(token):
        raise _Refused
    return int(token)


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _Refused
        result[key] = value
    return result


def load_json_bytes(data: bytes) -> Any:
    """Parse `data` as strict content JSON, or raise `ContentLoadError`."""
    if data.startswith(_BOM):
        raise ContentLoadError("a UTF-8 BOM is not allowed", line=1, column=1)
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        line, column = _position(data[: error.start].decode("utf-8"), error.start)
        raise ContentLoadError("invalid UTF-8", line=line, column=column) from None
    try:
        result = json.loads(
            text,
            parse_float=_refuse,
            parse_int=_integer,
            parse_constant=_refuse,
            object_pairs_hook=_pairs,
        )
    except json.JSONDecodeError as error:
        raise ContentLoadError(error.msg, line=error.lineno, column=error.colno) from None
    except (_Refused, RecursionError):
        _locate(text)
    if _is_too_deep(result) or (b"\\u" in data and _has_surrogate(result)):
        _locate(text)
    return result


def load_json_file(path: Path) -> Any:
    """Read and parse one file with `load_json_bytes`."""
    return load_json_bytes(path.read_bytes())


def _locate(text: str) -> NoReturn:
    index = _too_deep(text)
    if index is not None:
        line, column = _position(text, index)
        raise ContentLoadError(
            f"nested more than {MAX_DEPTH} levels deep", line=line, column=column
        )
    _Scanner(text).locate()
    raise AssertionError("unreachable: the scan always finds what the checks refused")


def _is_too_deep(value: Any) -> bool:
    """Whether a parsed value nests past `MAX_DEPTH`, walked one level at a time."""
    level = [value] if isinstance(value, dict | list) else []
    for _ in range(MAX_DEPTH):
        below: list[Any] = []
        for item in level:
            children = item.values() if isinstance(item, dict) else item
            below.extend(child for child in children if isinstance(child, dict | list))
        if not below:
            return False
        level = below
    return True


def _too_deep(text: str) -> int | None:
    """The index of the first bracket past `MAX_DEPTH`, without recursing."""
    depth = 0
    for match in _TOKEN.finditer(text):
        token = match.group()
        if token in ("[", "{"):
            depth += 1
            if depth > MAX_DEPTH:
                return match.start()
        elif token in ("]", "}"):
            depth -= 1
    return None


def _has_surrogate(value: Any) -> bool:
    stack = [value]
    while stack:
        item = stack.pop()
        if isinstance(item, str):
            if _SURROGATE.search(item):
                return True
        elif isinstance(item, list):
            stack.extend(item)
        elif isinstance(item, dict):
            stack.extend(item)
            stack.extend(item.values())
    return False


def _position(text: str, index: int) -> tuple[int, int]:
    line = text.count("\n", 0, index) + 1
    column = index - text.rfind("\n", 0, index)
    return line, column


class _Scanner:
    """Walks a document the fast path refused, and raises at the first refused token."""

    def __init__(self, text: str) -> None:
        self.text = text

    def fail(self, message: str, index: int) -> ContentLoadError:
        line, column = _position(self.text, index)
        return ContentLoadError(message, line=line, column=column)

    def skip(self, index: int) -> int:
        match = _WHITESPACE.match(self.text, index)
        return match.end() if match else index

    def locate(self) -> None:
        self.value(self.skip(0))

    def string(self, index: int) -> tuple[str, int]:
        text, end = scanstring(self.text, index + 1, True)
        if _SURROGATE.search(text):
            raise self.fail("a lone surrogate is not allowed in a string", index)
        return text, end

    def value(self, index: int) -> int:
        text = self.text
        char = text[index] if index < len(text) else ""
        if char == "{":
            return self.object(index + 1)
        if char == "[":
            return self.array(index + 1)
        if char == '"':
            return self.string(index)[1]
        for constant in _CONSTANTS:
            if text.startswith(constant, index):
                raise self.fail(f"{constant} is not allowed: content numbers are integers", index)
        for literal in ("true", "false", "null"):
            if text.startswith(literal, index):
                return index + len(literal)
        match = _NUMBER.match(text, index)
        if match is None:  # pragma: no cover - the fast path already refused bad syntax
            raise self.fail("expecting a value", index)
        if match.group(1) or match.group(2):
            raise self.fail("only integers are allowed: no fraction or exponent", index)
        if not _in_range(match.group()):
            raise self.fail("integer out of range: content integers are within ±(2^53 - 1)", index)
        return match.end()

    def object(self, index: int) -> int:
        seen: set[str] = set()
        index = self.skip(index)
        if self.text.startswith("}", index):
            return index + 1
        while True:
            key, end = self.string(index)
            if key in seen:
                raise self.fail(f"duplicate key {key!r}", index)
            seen.add(key)
            index = self.skip(end)
            index = self.skip(index + 1)  # the colon
            index = self.skip(self.value(index))
            if self.text.startswith("}", index):
                return index + 1
            index = self.skip(index + 1)  # the comma

    def array(self, index: int) -> int:
        index = self.skip(index)
        if self.text.startswith("]", index):
            return index + 1
        while True:
            index = self.skip(self.value(index))
            if self.text.startswith("]", index):
                return index + 1
            index = self.skip(index + 1)  # the comma
