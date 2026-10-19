"""The breaking-change check (FR-010, research R3)."""

import copy
import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

from wassal_content.schema_diff import Change, check_sets, diff_schemas, read_tree_at

BASE: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://wassal.invalid/content/1/thing.schema.json",
    "title": "Thing",
    "type": "object",
    "required": ["a", "kind"],
    "properties": {
        "a": {"type": "integer", "minimum": 0, "maximum": 10, "multipleOf": 50},
        "kind": {"$ref": "#/$defs/Kind"},
        "name": {"type": "string", "pattern": "^[a-z]+$", "maxLength": 20, "minLength": 1},
        "tags": {"type": "array", "items": {"type": "string"}, "maxItems": 5},
        "tray": {
            "type": "object",
            "propertyNames": {"type": "string"},
            "additionalProperties": {"type": "integer"},
        },
    },
    "additionalProperties": False,
    "$defs": {"Kind": {"type": "string", "enum": ["x", "y"]}},
}


def _breaks(mutate: Any) -> list[str]:
    new = copy.deepcopy(BASE)
    mutate(new)
    return [
        c.pointer for c in diff_schemas({"thing.schema.json": BASE}, {"thing.schema.json": new})
    ]


def _set(path: list[str], value: Any) -> Any:
    def apply(doc: dict[str, Any]) -> None:
        for key in path[:-1]:
            doc = doc[key]
        doc[path[-1]] = value

    return apply


def _drop(path: list[str]) -> Any:
    def apply(doc: dict[str, Any]) -> None:
        for key in path[:-1]:
            doc = doc[key]
        del doc[path[-1]]

    return apply


@pytest.mark.parametrize(
    ("mutate", "pointer"),
    [
        (_drop(["properties", "name"]), "/properties/name"),
        (_set(["properties", "a", "type"], "string"), "/properties/a"),
        (_set(["$defs", "Kind", "enum"], ["x"]), "/$defs/Kind/enum"),
        (_set(["properties", "a", "minimum"], 1), "/properties/a/minimum"),
        (_set(["properties", "a", "maximum"], 9), "/properties/a/maximum"),
        (_set(["properties", "a", "multipleOf"], 100), "/properties/a/multipleOf"),
        (_set(["properties", "name", "pattern"], "^[a-y]+$"), "/properties/name/pattern"),
        (_set(["properties", "name", "maxLength"], 19), "/properties/name/maxLength"),
        (_set(["properties", "name", "minLength"], 2), "/properties/name/minLength"),
        (_set(["properties", "tags", "maxItems"], 4), "/properties/tags/maxItems"),
        (_set(["properties", "tags", "uniqueItems"], True), "/properties/tags/uniqueItems"),
        (_set(["required"], ["a", "kind", "name"]), "/required"),
        (
            _set(["properties", "tray", "additionalProperties"], False),
            "/properties/tray/additionalProperties",
        ),
        (_set(["properties", "kind", "$ref"], "#/$defs/Other"), "/properties/kind"),
        (_drop(["$defs", "Kind"]), "/$defs/Kind"),
        (_set(["properties", "tags", "items"], {"type": "integer"}), "/properties/tags/items"),
    ],
)
def test_breaking_changes_are_reported(mutate: Any, pointer: str) -> None:
    assert pointer in _breaks(mutate)


@pytest.mark.parametrize(
    "mutate",
    [
        _set(["properties", "extra"], {"type": "string"}),
        _set(["$defs", "Kind", "enum"], ["x", "y", "z"]),
        _set(["description"], "now documented"),
        _set(["properties", "a", "minimum"], -5),
        _set(["properties", "a", "maximum"], 20),
        _set(["properties", "a", "multipleOf"], 25),
        _set(["required"], ["a"]),
        _set(["$defs", "New"], {"type": "string"}),
    ],
)
def test_widening_changes_are_not_breaking(mutate: Any) -> None:
    assert _breaks(mutate) == []


def test_a_removed_file_breaks() -> None:
    changes = diff_schemas({"thing.schema.json": BASE}, {})
    assert changes == [Change("thing.schema.json", "", "the schema file was removed")]
    assert str(changes[0]) == "thing.schema.json#: the schema file was removed"


def _files(schema: dict[str, Any], version: str) -> dict[str, bytes]:
    return {
        "thing.schema.json": json.dumps(schema).encode(),
        "schema-set.json": json.dumps({"version": version}).encode(),
    }


def test_a_breaking_change_fails_only_once_active_and_without_a_major_bump() -> None:
    broken = copy.deepcopy(BASE)
    del broken["properties"]["name"]
    assert not check_sets(_files(BASE, "1.0"), _files(broken, "1.1"), active=True).ok
    assert check_sets(_files(BASE, "1.0"), _files(broken, "2.0"), active=True).ok
    assert check_sets(_files(BASE, "1.0"), _files(broken, "1.1"), active=False).ok


def test_no_base_set_means_nothing_to_compare() -> None:
    result = check_sets({}, _files(BASE, "1.0"), active=True)
    assert result.ok
    assert result.breaking == ()


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


def test_reads_a_schema_tree_from_git(tmp_path: Path) -> None:
    _git(tmp_path, "init", "-q")
    schemas = tmp_path / "content" / "schemas"
    schemas.mkdir(parents=True)
    for name, data in _files(BASE, "1.0").items():
        (schemas / name).write_bytes(data)
    _git(tmp_path, "add", ".")
    _git(tmp_path, "-c", "user.name=t", "-c", "user.email=t@t.invalid", "commit", "-qm", "base")
    assert read_tree_at("HEAD", tmp_path) == _files(BASE, "1.0")
    assert read_tree_at("HEAD", tmp_path, "content/elsewhere") == {}
    with pytest.raises(ValueError, match="not a git revision"):
        read_tree_at("no-such-ref", tmp_path)


def test_reads_names_with_spaces_and_non_ascii(tmp_path: Path) -> None:
    _git(tmp_path, "init", "-q")
    schemas = tmp_path / "content" / "schemas"
    schemas.mkdir(parents=True)
    names = ["a b.schema.json", "é.schema.json"]
    for name in names:
        (schemas / name).write_bytes(b"{}")
    _git(tmp_path, "add", ".")
    _git(tmp_path, "-c", "user.name=t", "-c", "user.email=t@t.invalid", "commit", "-qm", "base")
    assert sorted(read_tree_at("HEAD", tmp_path)) == sorted(names)


@pytest.mark.parametrize("ref", ["--output=/tmp/x", "-h", ""])
def test_a_ref_that_looks_like_an_option_is_refused(tmp_path: Path, ref: str) -> None:
    _git(tmp_path, "init", "-q")
    with pytest.raises(ValueError, match="git revision"):
        read_tree_at(ref, tmp_path)


def test_a_malformed_schema_set_is_a_value_error() -> None:
    new = {**_files(BASE, "1.0"), "schema-set.json": b'{"min_client_version_by_major": {}}'}
    with pytest.raises(ValueError, match=r"schema-set\.json"):
        check_sets(_files(BASE, "1.0"), new, active=True)
