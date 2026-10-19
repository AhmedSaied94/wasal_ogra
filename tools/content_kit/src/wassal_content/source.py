"""The `content/source` layout: reading, assembling and writing (contracts/content-source.md).

One layout serves the repository's `content/source/`, the sample in `content/examples/sample/`
and the admin's zip import and export. Every file is one pack part and is validated against that
part's schema on its own, so a report can name the file and the field.

`read_files` works on a mapping of relative paths to bytes, so the importer can feed it a zip's
entries after its own size and path checks. `read_layout` reads a directory into that mapping.
"""

from __future__ import annotations

import json
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Any

from wassal_content.findings import Finding
from wassal_content.loader import ContentLoadError, load_json_bytes
from wassal_content.schemas import IDENTIFIER_FIELDS, SchemaSet, default_schema_set

__all__ = [
    "FOLDERS",
    "SourceTree",
    "assemble_pack",
    "export_bytes",
    "pack_to_files",
    "read_files",
    "read_layout",
    "write_layout",
]

# Folder → (pack array, part). Each file in the folder is one element, named by its identifier.
FOLDERS: Mapping[str, tuple[str, str]] = {
    "lines": ("lines", "line"),
    "vehicles": ("vehicles", "vehicle"),
    "chapters": ("chapters", "chapter"),
    "rooms": ("rooms", "room"),
    "items": ("items", "item"),
    "family_requests": ("family_requests", "family_request"),
    "speech": ("speech_pools", "speech_pool"),
}
# Root files holding an array of elements.
ARRAY_FILES: Mapping[str, tuple[str, str]] = {
    "daily_rewards.json": ("daily_rewards", "daily_reward"),
    "tasks.json": ("tasks", "task"),
}
_PACK_ARRAYS = (
    "lines",
    "vehicles",
    "trips",
    "chapters",
    "rooms",
    "items",
    "family_requests",
    "speech_pools",
    "daily_rewards",
    "tasks",
)
_SORT_KEYS: Mapping[str, str] = {
    "lines": "line_id",
    "vehicles": "vehicle_id",
    "trips": "trip_id",
    "chapters": "chapter_id",
    "rooms": "room_id",
    "items": "item_id",
    "family_requests": "request_id",
    "speech_pools": "speech_key",
    "tasks": "task_id",
}
_IGNORED = frozenset({"README.md"})
_REQUIRED = ("catalog.json", "daily_rewards.json", "tasks.json")
_SCHEMA_VERSION = re.compile(r"^[0-9]+\.[0-9]+\Z")
_META_KEYS = ("pack_id", "schema_version", "version")


@dataclass
class SourceTree:
    """The parts of one layout. `meta` is `pack.json`, or None when the layout is empty."""

    meta: dict[str, Any] | None = None
    parts: dict[str, list[dict[str, Any]]] = field(
        default_factory=lambda: {name: [] for name in _PACK_ARRAYS}
    )
    catalog: dict[str, Any] | None = None

    @property
    def is_empty(self) -> bool:
        return self.meta is None and self.catalog is None and not any(self.parts.values())


def export_bytes(document: Any) -> bytes:
    """A file in the export format: sorted keys, 2-space indent, UTF-8, trailing newline."""
    return (json.dumps(document, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()


def read_layout(
    root: Path, schema_set: SchemaSet | None = None
) -> tuple[SourceTree, list[Finding]]:
    """Read a layout directory. Symlinks are refused, and README.md at the root is ignored."""
    if not root.is_dir():
        raise FileNotFoundError(f"{root} is not a directory")
    files: dict[str, bytes] = {}
    refused: list[Finding] = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            refused.append(_layout(relative, "symlinks are not allowed in a layout"))
        elif path.is_file():
            files[relative] = path.read_bytes()
    tree, findings = read_files(files, schema_set)
    return tree, sorted([*refused, *findings])


def read_files(
    files: Mapping[str, bytes], schema_set: SchemaSet | None = None
) -> tuple[SourceTree, list[Finding]]:
    """Read a layout given as relative POSIX paths and their bytes."""
    reader = _Reader(schema_set or default_schema_set())
    for relative in sorted(files):
        reader.read(relative, files[relative])
    reader.finish()
    return reader.tree, sorted(reader.findings)


def _layout(relative: str, message: str, path: str = "$") -> Finding:
    return Finding(path=path, code="V-LY", message=message, file=relative)


class _Reader:
    def __init__(self, schema_set: SchemaSet) -> None:
        self.schema_set = schema_set
        self.tree = SourceTree()
        self.findings: list[Finding] = []
        self.seen: set[str] = set()

    def read(self, relative: str, data: bytes) -> None:
        parts = PurePosixPath(relative).parts
        if relative in _IGNORED:
            return
        if any(part.startswith(".") for part in parts) or not relative.endswith(".json"):
            self.findings.append(_layout(relative, "not a file of the content/source layout"))
            return
        self.seen.add(relative)
        if len(parts) == 1:
            self.root_file(relative, data)
        elif len(parts) == 2 and parts[0] in FOLDERS:
            array, part = FOLDERS[parts[0]]
            self.element(relative, data, array, part)
        elif len(parts) == 3 and parts[0] == "trips":
            self.element(relative, data, "trips", "trip", line_folder=parts[1])
        else:
            self.findings.append(_layout(relative, "not a file of the content/source layout"))

    def load(self, relative: str, data: bytes) -> Any:
        try:
            return load_json_bytes(data)
        except ContentLoadError as error:
            self.findings.append(Finding(path="$", code="V-JS", message=str(error), file=relative))
            return None

    def root_file(self, relative: str, data: bytes) -> None:
        if relative == "pack.json":
            document = self.load(relative, data)
            if document is not None:
                self.meta(relative, document)
        elif relative == "catalog.json":
            document = self.load(relative, data)
            if document is not None and self.valid("catalog", document, relative):
                self.tree.catalog = document
        elif relative in ARRAY_FILES:
            array, part = ARRAY_FILES[relative]
            document = self.load(relative, data)
            if document is None:
                return
            if not isinstance(document, list):
                self.findings.append(
                    Finding(path="$", code="V-SC", message="must be an array", file=relative)
                )
                return
            for index, element in enumerate(document):
                if self.valid(part, element, relative, prefix=f"$[{index}]"):
                    self.tree.parts[array].append(element)
        else:
            self.findings.append(_layout(relative, "not a file of the content/source layout"))

    def meta(self, relative: str, document: Any) -> None:
        def problem(path: str, message: str) -> None:
            self.findings.append(Finding(path=path, code="V-SC", message=message, file=relative))

        if not isinstance(document, dict):
            problem("$", "pack.json must be an object")
            return
        before = len(self.findings)
        for key in sorted(set(document) - set(_META_KEYS)):
            problem(f"$.{key}", f"{key!r} is not an allowed property")
        for key in _META_KEYS:
            if key not in document:
                problem(f"$.{key}", f"{key!r} is required")
        if "pack_id" in document and document["pack_id"] != "core":
            problem("$.pack_id", "pack_id must be 'core'")
        version = document.get("schema_version")
        if "schema_version" in document and not (
            isinstance(version, str) and _SCHEMA_VERSION.match(version)
        ):
            problem("$.schema_version", "schema_version must be <major>.<minor>")
        number = document.get("version")
        if "version" in document and (type(number) is not int or number < 0):
            problem("$.version", "version must be an integer of at least 0")
        if len(self.findings) == before:
            self.tree.meta = document

    def element(
        self, relative: str, data: bytes, array: str, part: str, *, line_folder: str | None = None
    ) -> None:
        document = self.load(relative, data)
        if document is None or not self.valid(part, document, relative):
            return
        id_field = IDENTIFIER_FIELDS[part]
        stem = PurePosixPath(relative).name.removesuffix(".json")
        if str(document[id_field]) != stem:
            self.findings.append(
                _layout(relative, f"the file name must be its {id_field}", f"$.{id_field}")
            )
            return
        if line_folder is not None and document["line_id"] != line_folder:
            self.findings.append(
                _layout(relative, "a trip lives in its own line's folder", "$.line_id")
            )
            return
        self.tree.parts[array].append(document)

    def valid(self, part: str, document: Any, relative: str, *, prefix: str = "$") -> bool:
        findings = self.schema_set.validate_document(part, document, file=relative)
        for finding in findings:
            path = prefix + finding.path.removeprefix("$")
            self.findings.append(
                Finding(
                    path=path,
                    code=finding.code,
                    message=finding.message,
                    entity=finding.entity,
                    id=finding.id,
                    file=relative,
                )
            )
        return not findings

    def finish(self) -> None:
        anything = bool(self.seen - {"pack.json"})
        if "pack.json" not in self.seen:
            if anything:
                self.findings.append(_layout("pack.json", "pack.json is missing"))
            return
        for required in _REQUIRED:
            if required not in self.seen:
                self.findings.append(_layout(required, f"{required} is missing"))


def assemble_pack(tree: SourceTree, version: int) -> dict[str, Any]:
    """The `Pack` a build of the same content produces: arrays sorted by identifier.

    Catalog prices are sorted by `(sku_kind, sku_id)` and daily rewards by `day_index`, because
    neither has an authored order.
    """
    if tree.meta is None or tree.catalog is None:
        raise ValueError("a pack needs pack.json and catalog.json")
    pack: dict[str, Any] = {
        "pack_id": tree.meta["pack_id"],
        "version": version,
        "schema_version": tree.meta["schema_version"],
    }
    for array in _PACK_ARRAYS:
        if array == "daily_rewards":
            pack[array] = sorted(tree.parts[array], key=lambda day: int(day["day_index"]))
        else:
            key = _SORT_KEYS[array]
            pack[array] = sorted(tree.parts[array], key=lambda element: str(element[key]))
    prices = sorted(tree.catalog["prices"], key=lambda p: (str(p["sku_kind"]), str(p["sku_id"])))
    pack["catalog"] = {**tree.catalog, "prices": prices}
    return pack


def _component(value: Any) -> str:
    """An identifier used as a file or folder name. The schemas' patterns already ensure this."""
    if (
        not isinstance(value, str)
        or not value
        or value.startswith(".")
        or any(char in value for char in "/\\\0")
    ):
        raise ValueError(f"{value!r} can't be a path component")
    return value


def pack_to_files(pack: Mapping[str, Any], version: int) -> dict[str, bytes]:
    """Split a pack into its layout files, in the export format."""
    meta = {
        "pack_id": pack["pack_id"],
        "schema_version": pack["schema_version"],
        "version": version,
    }
    files = {
        "pack.json": export_bytes(meta),
        "catalog.json": export_bytes(pack["catalog"]),
        "daily_rewards.json": export_bytes(pack["daily_rewards"]),
        "tasks.json": export_bytes(pack["tasks"]),
    }
    for folder, (array, part) in FOLDERS.items():
        id_field = IDENTIFIER_FIELDS[part]
        for element in pack[array]:
            files[f"{folder}/{_component(element[id_field])}.json"] = export_bytes(element)
    for trip in pack["trips"]:
        line_id, trip_id = _component(trip["line_id"]), _component(trip["trip_id"])
        files[f"trips/{line_id}/{trip_id}.json"] = export_bytes(trip)
    return files


def write_layout(pack: Mapping[str, Any], root: Path, version: int) -> None:
    """Write a pack as a layout under `root`, which must not hold an older layout."""
    if root.is_dir() and any(root.iterdir()):
        raise ValueError(f"{root} is not empty: write a layout into a new directory")
    for relative, data in pack_to_files(pack, version).items():
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
