"""The schema profile (research R3).

Only a small set of JSON Schema keywords is allowed, so that one generator can map every schema to
both Pydantic and Dart with the same meaning, and "absent" has exactly one representation:

- no `null`, `number`, `default`, combinators (`oneOf`, `anyOf`, `allOf`, `not`) or conditionals;
- every object is closed (`additionalProperties: false`), except maps, which pair a value schema
  with `propertyNames` and have no `properties`;
- `$ref` points at another file of the set, or a `$defs` entry, by relative reference;
- bounds are integers within the loader's safe range, and a `pattern` starts with `^`, compiles,
  and spells out its character classes (`\\d`, `\\w`, `\\s` and `\\b` mean different things in
  ECMA-262 and Python).

CI runs this check over `content/schemas/`, and the generator refuses anything outside it.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from wassal_content.loader import SAFE_INTEGER

__all__ = ["DRAFT", "ID_BASE", "ProfileViolation", "check_profile"]

DRAFT = "https://json-schema.org/draft/2020-12/schema"
ID_BASE = "https://wassal.invalid/content/"

_ROOT_ONLY = frozenset({"$schema", "$id", "$defs"})
_ANNOTATIONS = frozenset({"title", "description", "$comment"})
_KEYWORDS = frozenset(
    {
        "$ref",
        "type",
        "properties",
        "required",
        "additionalProperties",
        "propertyNames",
        "enum",
        "const",
        "minimum",
        "maximum",
        "multipleOf",
        "minLength",
        "maxLength",
        "pattern",
        "items",
        "minItems",
        "maxItems",
        "uniqueItems",
    }
)
_TYPES = frozenset({"object", "array", "string", "integer", "boolean"})
_REF = re.compile(
    r"^(?:#/\$defs/[A-Za-z][A-Za-z0-9]*"
    r"|[a-z][a-z0-9_]*\.schema\.json(?:#/\$defs/[A-Za-z][A-Za-z0-9]*)?)$"
)
# A shorthand class: \d, \w, \s or \b (or their negations) after an even number of backslashes.
_SHORTHAND = re.compile(r"(?:^|[^\\])(?:\\\\)*\\[dDwWsSbB]")
# The lowest value of each integer keyword; the highest is SAFE_INTEGER.
_INTEGER_KEYWORDS = {
    "minimum": -SAFE_INTEGER,
    "maximum": -SAFE_INTEGER,
    "multipleOf": 1,
    "minLength": 0,
    "maxLength": 0,
    "minItems": 0,
    "maxItems": 0,
}
_ID = re.compile(
    r"^https://wassal\.invalid/content/[0-9]+/(?P<file>[a-z][a-z0-9_]*\.schema\.json)$"
)


@dataclass(frozen=True)
class ProfileViolation:
    """A schema construct outside the profile. `pointer` is a JSON Pointer into the file."""

    file: str
    pointer: str
    message: str


def check_profile(schemas: Mapping[str, Any]) -> list[ProfileViolation]:
    """Check every schema file (file name to parsed document) against the profile."""
    violations: list[ProfileViolation] = []
    for file, document in sorted(schemas.items()):
        violations.extend(_Checker(file).root(document))
    return violations


def _escape(token: str) -> str:
    return token.replace("~", "~0").replace("/", "~1")


class _Checker:
    def __init__(self, file: str) -> None:
        self.file = file
        self.found: list[ProfileViolation] = []

    def report(self, pointer: str, message: str) -> None:
        self.found.append(ProfileViolation(self.file, pointer, message))

    def root(self, document: Any) -> list[ProfileViolation]:
        if not isinstance(document, dict):
            self.report("", "a schema file must be a JSON object")
            return self.found
        if document.get("$schema") != DRAFT:
            self.report("/$schema", f"$schema must be {DRAFT}")
        match = _ID.match(str(document.get("$id", "")))
        if match is None or match.group("file") != self.file:
            self.report("/$id", f"$id must be {ID_BASE}<major>/{self.file}")
        defs = document.get("$defs", {})
        if not isinstance(defs, dict):
            self.report("/$defs", "$defs must be an object")
            defs = {}
        for name, schema in defs.items():
            self.node(schema, f"/$defs/{_escape(name)}", named=True)
        body = {key: value for key, value in document.items() if key not in _ROOT_ONLY}
        if set(body) - _ANNOTATIONS:
            if "title" not in body:
                self.report("/title", "a root type needs a title, which names its class")
            self.node(body, "", named=True)
        return self.found

    def node(self, schema: Any, pointer: str, *, named: bool = False) -> None:
        if not isinstance(schema, dict):
            self.report(pointer, "a schema must be an object")
            return
        for key in schema:
            if key in _ROOT_ONLY:
                self.report(f"{pointer}/{_escape(key)}", f"{key} is allowed only at a file's root")
            elif key not in _KEYWORDS and key not in _ANNOTATIONS:
                self.report(f"{pointer}/{_escape(key)}", f"{key} is outside the schema profile")
        if "$ref" in schema and not _REF.match(str(schema["$ref"])):
            self.report(
                f"{pointer}/$ref", "a $ref must be '#/$defs/<Name>' or '<file>.schema.json'"
            )
        self.values(schema, pointer)
        kind = schema.get("type")
        if kind is not None and (not isinstance(kind, str) or kind not in _TYPES):
            self.report(f"{pointer}/type", f"type must be one of {sorted(_TYPES)}")
            return
        if "enum" in schema:
            self.enum(schema, pointer)
        if kind == "object":
            self.object(schema, pointer, named=named)
        if kind == "array" or "items" in schema:
            self.node(schema.get("items"), f"{pointer}/items")

    def values(self, schema: dict[str, Any], pointer: str) -> None:
        for key, lowest in _INTEGER_KEYWORDS.items():
            value = schema.get(key, lowest)
            if type(value) is not int or not lowest <= value <= SAFE_INTEGER:
                self.report(
                    f"{pointer}/{key}", f"{key} must be an integer from {lowest} to 2^53 - 1"
                )
        if type(schema.get("uniqueItems", False)) is not bool:
            self.report(f"{pointer}/uniqueItems", "uniqueItems must be true or false")
        if "pattern" in schema:
            self.pattern(schema["pattern"], f"{pointer}/pattern")

    def pattern(self, pattern: Any, pointer: str) -> None:
        if not isinstance(pattern, str) or not pattern.startswith("^"):
            self.report(pointer, "a pattern is a string that starts with ^")
        elif _SHORTHAND.search(pattern):
            self.report(pointer, "a pattern spells out its classes: no \\d, \\w, \\s or \\b")
        else:
            try:
                re.compile(pattern)
            except re.error as error:
                self.report(pointer, f"the pattern doesn't compile: {error}")

    def enum(self, schema: dict[str, Any], pointer: str) -> None:
        values = schema["enum"]
        expected = {"string": str, "integer": int}.get(str(schema.get("type")))
        if (
            not isinstance(values, list)
            or not values
            or expected is None
            or any(type(value) is not expected for value in values)
            or len(set(values)) != len(values)
        ):
            self.report(
                f"{pointer}/enum", "an enum lists distinct values of its string or integer type"
            )

    def object(self, schema: dict[str, Any], pointer: str, *, named: bool) -> None:
        closed = schema.get("additionalProperties")
        if closed is False:
            properties = schema.get("properties")
            if not isinstance(properties, dict) or not properties:
                self.report(pointer, "a closed object lists its properties")
                return
            if not named:
                self.report(pointer, "an object with properties must be a $defs entry or a root")
            for name, child in properties.items():
                self.node(child, f"{pointer}/properties/{_escape(name)}")
            required = schema.get("required", [])
            if not isinstance(required, list) or any(name not in properties for name in required):
                self.report(f"{pointer}/required", "every required name must be a property")
            return
        if isinstance(closed, dict) and "propertyNames" in schema and "properties" not in schema:
            self.node(schema["propertyNames"], f"{pointer}/propertyNames")
            self.node(closed, f"{pointer}/additionalProperties")
            return
        self.report(
            pointer,
            "an object needs additionalProperties: false, or is a map with propertyNames and "
            "an additionalProperties schema",
        )
