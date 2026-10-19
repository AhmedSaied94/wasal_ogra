"""The schema set: every `*.schema.json` in one registry, and validation against a part (R2).

By default the schemas come from this package's own copy (`wassal_content/schemas/`), which
`wassal-content codegen` writes from `content/schemas/` and CI drift-checks. Setting
`WASSAL_CONTENT_SCHEMAS_DIR` reads another directory instead, which codegen and the tests use.
"""

from __future__ import annotations

import os
import re
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from functools import cache
from importlib import resources
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, ValidationError
from jsonschema.validators import extend
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

from wassal_content.findings import Finding
from wassal_content.loader import load_json_bytes

__all__ = [
    "IDENTIFIER_FIELDS",
    "PARTS",
    "SchemaSet",
    "default_schema_set",
    "load_schema_set",
]

# Every root part, in the order the generator and the reports use.
PARTS = (
    "pack",
    "trip",
    "line",
    "vehicle",
    "chapter",
    "room",
    "item",
    "family_request",
    "speech_pool",
    "catalog",
    "daily_reward",
    "task",
    "manifest",
)

# The identifier field of each part that has one, used to name the entity in a finding.
IDENTIFIER_FIELDS: Mapping[str, str] = {
    "trip": "trip_id",
    "line": "line_id",
    "vehicle": "vehicle_id",
    "chapter": "chapter_id",
    "room": "room_id",
    "item": "item_id",
    "family_request": "request_id",
    "speech_pool": "speech_key",
    "daily_reward": "day_index",
    "task": "task_id",
    "pack": "pack_id",
}

# The pack's arrays, and the part each element is.
PACK_ARRAYS: Mapping[str, str] = {
    "lines": "line",
    "vehicles": "vehicle",
    "trips": "trip",
    "chapters": "chapter",
    "rooms": "room",
    "items": "item",
    "family_requests": "family_request",
    "speech_pools": "speech_pool",
    "daily_rewards": "daily_reward",
    "tasks": "task",
}

_SUFFIX = ".schema.json"


def _ecma_end_anchor(pattern: str) -> str:
    """ECMA-262's `$` doesn't match before a trailing newline, and Python's does: use `\\Z`.

    A final `$` is an anchor only when an even number of backslashes precedes it.
    """
    if not pattern.endswith("$"):
        return pattern
    body = pattern[:-1]
    backslashes = len(body) - len(body.rstrip("\\"))
    return body + r"\Z" if backslashes % 2 == 0 else pattern


def _pattern(
    validator: Any, pattern: str, instance: Any, schema: Mapping[str, Any]
) -> Iterator[ValidationError]:
    if not validator.is_type(instance, "string"):
        return
    compiled = re.compile(_ecma_end_anchor(pattern))
    if not compiled.search(instance):
        yield ValidationError(f"{instance!r} does not match {pattern!r}")


_Validator: Any = extend(Draft202012Validator, {"pattern": _pattern})  # type: ignore[no-untyped-call]


@dataclass(frozen=True)
class SchemaSet:
    """Every schema of one set, keyed by part, plus `schema-set.json`."""

    schemas: Mapping[str, Mapping[str, Any]]
    files: Mapping[str, bytes]
    meta: Mapping[str, Any]

    @property
    def version(self) -> str:
        return str(self.meta["version"])

    @property
    def major(self) -> int:
        return int(self.version.split(".")[0])

    @property
    def min_client_version_by_major(self) -> Mapping[str, str]:
        return dict(self.meta["min_client_version_by_major"])

    def registry(self) -> Registry[Any]:
        resources_: list[tuple[str, Resource[Any]]] = [
            (str(schema["$id"]), DRAFT202012.create_resource(dict(schema)))
            for schema in self.schemas.values()
        ]
        return Registry().with_resources(resources_)

    def validator_for(self, part: str) -> Any:
        """A 2020-12 validator for `part`, resolving cross-file `$ref`s offline."""
        if part not in PARTS:
            raise KeyError(f"unknown part {part!r}; known parts: {', '.join(PARTS)}")
        return _Validator(dict(self.schemas[part]), registry=self.registry())

    def validate_document(
        self, part: str, document: Any, *, file: str | None = None
    ) -> list[Finding]:
        """Every schema violation of `document` as `part`, sorted by path."""
        findings: list[Finding] = []
        for error in self.validator_for(part).iter_errors(document):
            for path, message in _describe(error):
                entity, identifier = _locate(part, document, path)
                findings.append(
                    Finding(
                        path=_json_path(path),
                        code="V-SC",
                        message=message,
                        entity=entity,
                        id=identifier,
                        file=file,
                    )
                )
        return sorted(set(findings))


def _describe(error: ValidationError) -> list[tuple[list[str | int], str]]:
    """Name the field at fault: a missing or unexpected property is reported at its own path."""
    path = list(error.absolute_path)
    schema = error.schema if isinstance(error.schema, Mapping) else {}
    if error.validator == "required" and isinstance(error.instance, dict):
        required = error.validator_value if isinstance(error.validator_value, list) else []
        missing = [name for name in required if name not in error.instance]
        return [([*path, name], f"{name!r} is required") for name in missing]
    if error.validator == "additionalProperties" and isinstance(error.instance, dict):
        allowed = set(schema.get("properties", {}))
        extra = sorted(name for name in error.instance if name not in allowed)
        if extra and schema.get("additionalProperties") is False:
            return [([*path, name], f"{name!r} is not an allowed property") for name in extra]
    return [(path, error.message)]


def _json_path(path: list[str | int]) -> str:
    text = "$"
    for element in path:
        text += f"[{element}]" if isinstance(element, int) else f".{element}"
    return text


def _locate(part: str, document: Any, path: list[str | int]) -> tuple[str, str]:
    """The entity and identifier a path points into, for reports."""
    if part == "pack" and len(path) >= 2 and isinstance(document, dict):
        array, index = path[0], path[1]
        element_part = PACK_ARRAYS.get(str(array))
        items = document.get(str(array))
        if (
            element_part
            and isinstance(index, int)
            and isinstance(items, list)
            and index < len(items)
        ):
            return element_part, _identifier(element_part, items[index])
    return part, _identifier(part, document)


def _identifier(part: str, document: Any) -> str:
    field = IDENTIFIER_FIELDS.get(part)
    if field and isinstance(document, dict) and field in document:
        return str(document[field])
    return ""


def load_schema_set(directory: Path) -> SchemaSet:
    """Read every schema of `directory` with the strict loader."""
    files = {path.name: path.read_bytes() for path in sorted(directory.iterdir()) if path.is_file()}
    return _build(files)


def _build(files: Mapping[str, bytes]) -> SchemaSet:
    schemas: dict[str, Mapping[str, Any]] = {}
    for name, data in files.items():
        if name.endswith(_SUFFIX):
            schemas[name.removesuffix(_SUFFIX)] = load_json_bytes(data)
    meta = load_json_bytes(files["schema-set.json"])
    return SchemaSet(schemas=schemas, files=dict(files), meta=meta)


@cache
def default_schema_set() -> SchemaSet:
    """The packaged schema set, or `WASSAL_CONTENT_SCHEMAS_DIR` when it is set."""
    override = os.environ.get("WASSAL_CONTENT_SCHEMAS_DIR")
    if override:
        return load_schema_set(Path(override))
    package = resources.files("wassal_content").joinpath("schemas")
    files = {
        entry.name: entry.read_bytes()
        for entry in sorted(package.iterdir(), key=lambda entry: entry.name)
        if entry.is_file() and (entry.name.endswith(_SUFFIX) or entry.name == "schema-set.json")
    }
    return _build(files)
