"""`wassal-content codegen`: the server models, the app models and the packaged copies.

Every output is generated in memory from `content/schemas/`, plus the packaged copy of the
engine's capabilities file, `content/engine/capabilities.json` (specs/004 research R13), which is
copied byte for byte once it parses. Writing replaces the managed files and removes stale ones;
checking compares byte for byte and lists every difference, which is how CI catches a schema
changed without regenerating, or a generated file edited by hand (FR-007).
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from wassal_content.codegen.dart import emit_dart
from wassal_content.codegen.ir import CodegenError, Model, build_model
from wassal_content.codegen.python import emit_python
from wassal_content.engine import CAPABILITIES_FILE, CapabilitiesError, parse_capabilities
from wassal_content.loader import ContentLoadError, load_json_bytes

__all__ = [
    "CodegenError",
    "Outputs",
    "build_from_dir",
    "check_outputs",
    "outputs_for",
    "read_capabilities",
    "write_outputs",
]

_SUFFIX = ".schema.json"

# build_runner writes these next to the generated libraries; they are its files, not stale ones.
_BUILD_RUNNER_PARTS = (".freezed.dart", ".g.dart")


@dataclass(frozen=True)
class Outputs:
    """Generated files by absolute path, and the directories whose other files are stale."""

    files: Mapping[Path, bytes]
    managed: Mapping[Path, str]  # directory → the glob of files it manages


def build_from_dir(schemas_dir: Path) -> tuple[Model, dict[str, bytes]]:
    """Parse a schema directory into the model, and return the raw files for copying."""
    raw = {path.name: path.read_bytes() for path in sorted(schemas_dir.iterdir()) if path.is_file()}
    if "schema-set.json" not in raw:
        raise CodegenError(f"{schemas_dir}/schema-set.json is missing")
    parsed = {
        name: _load(schemas_dir / name, data)
        for name, data in raw.items()
        if name.endswith(_SUFFIX) or name == "schema-set.json"
    }
    schema_set = parsed.pop("schema-set.json")
    schemas = {name.removesuffix(_SUFFIX): doc for name, doc in parsed.items()}
    version = schema_set.get("version") if isinstance(schema_set, dict) else None
    if not isinstance(version, str):
        raise CodegenError(f"{schemas_dir}/schema-set.json needs a version string")
    copies = {
        name: data
        for name, data in raw.items()
        if name.endswith(_SUFFIX) or name == "schema-set.json"
    }
    return build_model(schemas, version), copies


def _load(path: Path, data: bytes) -> Any:
    try:
        return load_json_bytes(data)
    except ContentLoadError as error:
        raise CodegenError(f"{path}: {error}") from None


def read_capabilities(path: Path) -> bytes:
    """The capabilities file's bytes, once they parse: the copy must be usable as well as equal."""
    if not path.is_file():
        raise CodegenError(f"{path} is missing")
    data = path.read_bytes()
    try:
        parse_capabilities(data)
    except CapabilitiesError as error:
        raise CodegenError(f"{path}: {error}") from None
    return data


def outputs_for(repo_root: Path) -> Outputs:
    """Every file codegen owns in the repository."""
    model, copies = build_from_dir(repo_root / "content" / "schemas")
    capabilities = read_capabilities(repo_root / "content" / "engine" / CAPABILITIES_FILE)
    package = repo_root / "tools" / "content_kit" / "src" / "wassal_content"
    dart_dir = repo_root / "packages" / "content_models" / "lib" / "src" / "generated"
    files: dict[Path, bytes] = {package / "models" / "_generated.py": emit_python(model)}
    files.update({package / "schemas" / name: data for name, data in copies.items()})
    files[package / "engine" / CAPABILITIES_FILE] = capabilities
    files.update({dart_dir / name: data for name, data in emit_dart(model).items()})
    managed = {package / "schemas": "*.json", package / "engine": "*.json", dart_dir: "*.dart"}
    return Outputs(files=files, managed=managed)


def _stale(outputs: Outputs) -> list[Path]:
    stale: list[Path] = []
    for directory, pattern in outputs.managed.items():
        if directory.is_dir():
            stale.extend(
                p
                for p in sorted(directory.glob(pattern))
                if p not in outputs.files and not p.name.endswith(_BUILD_RUNNER_PARTS)
            )
    return stale


def check_outputs(outputs: Outputs) -> list[Path]:
    """The generated files that are missing, differ, or are stale."""
    differing = [
        path
        for path, data in sorted(outputs.files.items())
        if not path.is_file() or path.read_bytes() != data
    ]
    return differing + _stale(outputs)


def write_outputs(outputs: Outputs) -> list[Path]:
    """Write every generated file that changed, remove stale ones, and return what changed."""
    changed = check_outputs(outputs)
    for path in changed:
        if path in outputs.files:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(outputs.files[path])
        else:
            path.unlink()
    return changed
