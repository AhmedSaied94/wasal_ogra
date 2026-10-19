"""The breaking-change check between two schema sets (FR-010, research R3).

A change breaks when a document valid under the base set can fail under the new one, or when an
older app's models can no longer read what the new set allows: a property removed or renamed, its
type changed, an enum value removed, a bound or pattern tightened, a property newly required, or a
map closed. CI refuses a breaking change unless the set's major version went up, and only once
`content/source/pack.json` exists, which is when a production pack exists.
"""

from __future__ import annotations

import subprocess
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from wassal_content.loader import ContentLoadError, load_json_bytes

__all__ = ["Change", "DiffResult", "check_sets", "diff_schemas", "read_tree_at"]

_SUFFIX = ".schema.json"
# keyword → True when a larger value is narrower (a lower bound).
_BOUNDS = {
    "minimum": True,
    "minLength": True,
    "minItems": True,
    "maximum": False,
    "maxLength": False,
    "maxItems": False,
}


@dataclass(frozen=True, order=True)
class Change:
    """One breaking change, located in the base schema file."""

    file: str
    pointer: str
    message: str

    def __str__(self) -> str:
        return f"{self.file}#{self.pointer}: {self.message}"


@dataclass(frozen=True)
class DiffResult:
    breaking: tuple[Change, ...]
    active: bool
    major_bumped: bool

    @property
    def ok(self) -> bool:
        return not self.active or self.major_bumped or not self.breaking


def _escape(token: str) -> str:
    return token.replace("~", "~0").replace("/", "~1")


class _Diff:
    def __init__(self, file: str) -> None:
        self.file = file
        self.changes: list[Change] = []

    def broke(self, pointer: str, message: str) -> None:
        self.changes.append(Change(self.file, pointer, message))

    def compare(self, base: Any, new: Any, pointer: str) -> None:
        if not isinstance(base, dict) or not isinstance(new, dict):
            if base != new:
                self.broke(pointer, "the schema changed shape")
            return
        if base.get("$ref") != new.get("$ref"):
            self.broke(pointer, f"$ref changed from {base.get('$ref')!r} to {new.get('$ref')!r}")
        if base.get("type") != new.get("type"):
            self.broke(pointer, f"type changed from {base.get('type')!r} to {new.get('type')!r}")
            return
        self.values(base, new, pointer)
        self.bounds(base, new, pointer)
        self.objects(base, new, pointer)
        for keyword in ("items", "propertyNames"):
            if keyword in base:
                if keyword in new:
                    self.compare(base[keyword], new[keyword], f"{pointer}/{keyword}")
                else:
                    self.broke(pointer, f"{keyword} was removed")
            elif keyword in new:
                self.broke(pointer, f"{keyword} was added")

    def values(self, base: dict[str, Any], new: dict[str, Any], pointer: str) -> None:
        if "enum" in base:
            removed = [v for v in base["enum"] if v not in new.get("enum", base["enum"])]
            if removed:
                self.broke(f"{pointer}/enum", f"enum values removed: {removed}")
        elif "enum" in new:
            self.broke(f"{pointer}/enum", "an enum was added to an open value")
        if base.get("const") != new.get("const") and "const" in new:
            self.broke(f"{pointer}/const", "const changed")
        if new.get("pattern") is not None and base.get("pattern") != new.get("pattern"):
            self.broke(f"{pointer}/pattern", "pattern changed")
        if new.get("uniqueItems") and not base.get("uniqueItems"):
            self.broke(f"{pointer}/uniqueItems", "items must now be unique")

    def bounds(self, base: dict[str, Any], new: dict[str, Any], pointer: str) -> None:
        for keyword, lower in _BOUNDS.items():
            if keyword not in new:
                continue
            old = base.get(keyword)
            if old is None or (new[keyword] > old if lower else new[keyword] < old):
                self.broke(
                    f"{pointer}/{keyword}", f"{keyword} tightened from {old} to {new[keyword]}"
                )
        step, old_step = new.get("multipleOf"), base.get("multipleOf")
        if step is not None and (old_step is None or old_step % step != 0):
            self.broke(f"{pointer}/multipleOf", f"multipleOf tightened from {old_step} to {step}")

    def objects(self, base: dict[str, Any], new: dict[str, Any], pointer: str) -> None:
        old_props, new_props = base.get("properties", {}), new.get("properties", {})
        for name, schema in old_props.items():
            child = f"{pointer}/properties/{_escape(name)}"
            if name in new_props:
                self.compare(schema, new_props[name], child)
            else:
                self.broke(child, f"property {name!r} was removed or renamed")
        for name in sorted(set(new.get("required", [])) - set(base.get("required", []))):
            self.broke(f"{pointer}/required", f"property {name!r} is newly required")
        old_extra, new_extra = base.get("additionalProperties"), new.get("additionalProperties")
        if isinstance(old_extra, dict):
            if new_extra is False:
                self.broke(f"{pointer}/additionalProperties", "a map was closed")
            elif isinstance(new_extra, dict):
                self.compare(old_extra, new_extra, f"{pointer}/additionalProperties")

    def document(self, base: dict[str, Any], new: dict[str, Any]) -> None:
        old_defs, new_defs = base.get("$defs", {}), new.get("$defs", {})
        for name, schema in old_defs.items():
            if name in new_defs:
                self.compare(schema, new_defs[name], f"/$defs/{_escape(name)}")
            else:
                self.broke(f"/$defs/{_escape(name)}", f"type {name!r} was removed")
        skip = {"$schema", "$id", "$defs"}
        self.compare(
            {k: v for k, v in base.items() if k not in skip},
            {k: v for k, v in new.items() if k not in skip},
            "",
        )


def diff_schemas(base: Mapping[str, Any], new: Mapping[str, Any]) -> list[Change]:
    """Every breaking change from `base` to `new` (file name → parsed schema)."""
    changes: list[Change] = []
    for file in sorted(base):
        if not file.endswith(_SUFFIX):
            continue
        diff = _Diff(file)
        if file not in new:
            diff.broke("", "the schema file was removed")
        else:
            diff.document(base[file], new[file])
        changes.extend(diff.changes)
    return sorted(changes)


def _load(name: str, data: bytes) -> Any:
    try:
        return load_json_bytes(data)
    except ContentLoadError as error:
        raise ValueError(f"{name}: {error}") from None


def _major(files: Mapping[str, bytes]) -> int | None:
    if "schema-set.json" not in files:
        return None
    document = _load("schema-set.json", files["schema-set.json"])
    version = document.get("version") if isinstance(document, dict) else None
    major = version.split(".")[0] if isinstance(version, str) else ""
    if not major.isdigit():
        raise ValueError("schema-set.json needs a version like '1.0'")
    return int(major)


def check_sets(
    base_files: Mapping[str, bytes], new_files: Mapping[str, bytes], *, active: bool
) -> DiffResult:
    """Compare two schema directories given as file name → bytes."""
    if not base_files:
        return DiffResult(breaking=(), active=active, major_bumped=False)
    base = {name: _load(name, data) for name, data in base_files.items() if name.endswith(_SUFFIX)}
    new = {name: _load(name, data) for name, data in new_files.items() if name.endswith(_SUFFIX)}
    old_major, new_major = _major(base_files), _major(new_files)
    bumped = old_major is not None and new_major is not None and new_major > old_major
    return DiffResult(tuple(diff_schemas(base, new)), active=active, major_bumped=bumped)


def read_tree_at(ref: str, repo_root: Path, directory: str = "content/schemas") -> dict[str, bytes]:
    """The files of `directory` at git revision `ref`, or nothing if it didn't exist there."""
    if not ref or ref.startswith("-"):
        raise ValueError(f"{ref!r} is not a git revision")
    listing = subprocess.run(
        ["git", "ls-tree", "-z", "--name-only", f"{ref}:{directory}"],
        cwd=repo_root,
        capture_output=True,
        check=False,
    )
    if listing.returncode != 0:
        verify = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
            cwd=repo_root,
            capture_output=True,
            check=False,
        )
        if verify.returncode != 0:
            raise ValueError(f"{ref!r} is not a git revision")
        return {}
    files: dict[str, bytes] = {}
    for name in filter(None, listing.stdout.decode().split("\0")):
        shown = subprocess.run(
            ["git", "show", f"{ref}:{directory}/{name}"],
            cwd=repo_root,
            capture_output=True,
            check=False,
        )
        if shown.returncode != 0:
            raise ValueError(
                f"git can't show {directory}/{name} at {ref!r}: {shown.stderr.decode()}"
            )
        files[name] = shown.stdout
    return files
