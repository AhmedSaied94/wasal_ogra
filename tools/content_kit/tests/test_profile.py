"""The schema profile (research R3): only the keywords the generator and the parity rules allow."""

from typing import Any

import pytest

from tests.paths import SCHEMAS
from wassal_content.loader import load_json_file
from wassal_content.profile import check_profile

ID = "https://wassal.invalid/content/1/"
DRAFT = "https://json-schema.org/draft/2020-12/schema"


def _root(file: str, **body: Any) -> dict[str, Any]:
    return {"$schema": DRAFT, "$id": ID + file, **body}


def _object(**properties: Any) -> dict[str, Any]:
    return {
        "title": "Thing",
        "type": "object",
        "required": [],
        "properties": properties,
        "additionalProperties": False,
    }


def _violations(schema: dict[str, Any], file: str = "thing.schema.json") -> list[tuple[str, str]]:
    return [(v.file, v.pointer) for v in check_profile({file: schema})]


def test_every_content_schema_passes() -> None:
    schemas = {path.name: load_json_file(path) for path in sorted(SCHEMAS.glob("*.schema.json"))}
    assert len(schemas) == 14
    assert check_profile(schemas) == []


@pytest.mark.parametrize(
    ("prop", "pointer"),
    [
        ({"type": "null"}, "/properties/a/type"),
        ({"type": "number"}, "/properties/a/type"),
        ({"type": ["string", "null"]}, "/properties/a/type"),
        ({"type": "integer", "default": 1}, "/properties/a/default"),
        ({"oneOf": [{"type": "string"}, {"type": "integer"}]}, "/properties/a/oneOf"),
        ({"anyOf": [{"type": "string"}]}, "/properties/a/anyOf"),
        ({"allOf": [{"type": "string"}]}, "/properties/a/allOf"),
        ({"type": "string", "if": {"minLength": 1}}, "/properties/a/if"),
        ({"type": "string", "not": {"minLength": 1}}, "/properties/a/not"),
        ({"type": "string", "format": "email"}, "/properties/a/format"),
        ({"type": "object", "properties": {}}, "/properties/a"),
        ({"type": "object", "additionalProperties": {"type": "integer"}}, "/properties/a"),
        ({"$ref": "https://example.com/x.json"}, "/properties/a/$ref"),
        ({"type": "integer", "minimum": 1.5}, "/properties/a/minimum"),
        ({"type": "integer", "maximum": True}, "/properties/a/maximum"),
        ({"type": "integer", "maximum": 2**53}, "/properties/a/maximum"),
        ({"type": "integer", "multipleOf": 0}, "/properties/a/multipleOf"),
        ({"type": "string", "maxLength": "3"}, "/properties/a/maxLength"),
        ({"type": "string", "minLength": -1}, "/properties/a/minLength"),
        (
            {"type": "array", "items": {"type": "integer"}, "maxItems": 2.0},
            "/properties/a/maxItems",
        ),
        (
            {"type": "array", "items": {"type": "integer"}, "uniqueItems": 1},
            "/properties/a/uniqueItems",
        ),
        ({"type": "string", "pattern": 5}, "/properties/a/pattern"),
        ({"type": "string", "pattern": "^[a-"}, "/properties/a/pattern"),
        ({"type": "string", "pattern": "[a-z]+$"}, "/properties/a/pattern"),
        ({"type": "string", "pattern": r"^\d+$"}, "/properties/a/pattern"),
        ({"type": "string", "pattern": r"^[a-z]\s[a-z]$"}, "/properties/a/pattern"),
    ],
    ids=lambda value: value if isinstance(value, str) else None,
)
def test_forbidden_constructs_are_refused_with_their_pointer(
    prop: dict[str, Any], pointer: str
) -> None:
    assert ("thing.schema.json", pointer) in _violations(
        _root("thing.schema.json", **_object(a=prop))
    )


def test_required_names_must_be_properties() -> None:
    schema = _root("thing.schema.json", **_object(a={"type": "string"}))
    schema["required"] = ["a", "b"]
    assert _violations(schema) == [("thing.schema.json", "/required")]


def test_a_root_object_needs_a_title() -> None:
    schema = _root("thing.schema.json", **_object(a={"type": "string"}))
    del schema["title"]
    assert _violations(schema) == [("thing.schema.json", "/title")]


def test_root_keywords_belong_only_at_the_root() -> None:
    schema = _root("thing.schema.json", **_object(a={"$id": ID + "x", "type": "string"}))
    assert _violations(schema) == [("thing.schema.json", "/properties/a/$id")]


def test_the_id_must_match_the_file_and_the_set() -> None:
    schema = _root("other.schema.json", **_object(a={"type": "string"}))
    assert _violations(schema) == [("thing.schema.json", "/$id")]


def test_the_draft_must_be_2020_12() -> None:
    schema = _root("thing.schema.json", **_object(a={"type": "string"}))
    schema["$schema"] = "http://json-schema.org/draft-07/schema#"
    assert _violations(schema) == [("thing.schema.json", "/$schema")]


def test_enum_values_must_match_the_type() -> None:
    schema = _root("thing.schema.json", **_object(a={"type": "string", "enum": ["x", 1]}))
    assert _violations(schema) == [("thing.schema.json", "/properties/a/enum")]


def test_a_map_is_allowed() -> None:
    schema = _root(
        "thing.schema.json",
        **_object(
            a={
                "type": "object",
                "propertyNames": {"type": "string", "pattern": "^[a-z]+$"},
                "additionalProperties": {"type": "integer"},
            }
        ),
    )
    assert _violations(schema) == []
