"""The fingerprints that tie a result to what made it (data-model.md "Fingerprints", research R12).

A content hash can't be forgotten the way a hand-bumped version can, and a stale result reused by
`input_key` (research R14) would be wrong.
"""

from __future__ import annotations

import hashlib
from functools import cache
from importlib import resources
from pathlib import Path

from wassal_content.canonical import canonical_bytes
from wassal_content.models import TripDefinition, to_json_dict

from wassal_solver.engine.params import TripParams

__all__ = ["input_key", "params_fingerprint", "solver_fingerprint"]

_HEX16 = 16
_SUFFIXES = (".py", ".json")
_CAPABILITIES = "capabilities.json"


def _package_root() -> Path:
    return Path(__file__).resolve().parent


@cache
def _installed() -> str:
    return _fingerprint(_package_root())


def solver_fingerprint(root: Path | None = None) -> str:
    """16 hex digits over every `.py` and `.json` file of the package at `root` (the installed
    one by default), in sorted path order, plus the content kit's packaged `capabilities.json`."""
    if root is None:
        return _installed()
    return _fingerprint(root)


def _fingerprint(root: Path) -> str:
    digest = hashlib.sha256()
    files = sorted(
        (path.relative_to(root).as_posix(), path)
        for path in root.rglob("*")
        if path.suffix in _SUFFIXES and path.is_file() and "__pycache__" not in path.parts
    )
    for relative, path in files:
        _add(digest, relative, path.read_bytes())
    capabilities = resources.files("wassal_content.engine").joinpath(_CAPABILITIES).read_bytes()
    _add(digest, f"wassal_content/engine/{_CAPABILITIES}", capabilities)
    return digest.hexdigest()[:_HEX16]


def _add(digest: hashlib._Hash, name: str, data: bytes) -> None:
    """One file: its name and its length, so neither can shift into the next file."""
    digest.update(f"{name}\n{len(data)}\n".encode())
    digest.update(data)


def params_fingerprint(params: TripParams) -> str:
    """16 hex digits of the SHA-256 of the canonical params."""
    return hashlib.sha256(canonical_bytes(params.to_json())).hexdigest()[:_HEX16]


def input_key(definition: TripDefinition, params: TripParams, *, solver: str | None = None) -> str:
    """What a result is reused by (research R14): 64 hex digits over the definition with its
    `rev` at 0, the params and the solver fingerprint. The `rev` is left out so that a new
    revision that plays the same reuses the old result."""
    document = to_json_dict(definition)
    document["rev"] = 0
    key = {
        "definition": document,
        "params": params.to_json(),
        "solver": solver_fingerprint() if solver is None else solver,
    }
    return hashlib.sha256(canonical_bytes(key)).hexdigest()
