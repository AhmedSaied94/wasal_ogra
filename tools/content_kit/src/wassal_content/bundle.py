"""The pack each app flavor bundles (specs/006-m04-content-loader/contracts/bundling.md).

`dev` builds the sample content as version 1, which must equal `sample.golden.json`. `release`
builds `content/source` at its `pack.json` version and checks it against production's release
record, fetched once over HTTPS and committed next to it. The app reads `bundled.json`, then the
file it names, and checks the file against it. Building reuses the pipeline's own steps, so a
bundled file is byte-identical to the one the server serves.
"""

from __future__ import annotations

import http.client
import re
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import IO, Any, Protocol

from wassal_content.canonical import canonical_bytes
from wassal_content.golden import GOLDEN_VERSION
from wassal_content.loader import ContentLoadError, load_json_bytes, load_json_file
from wassal_content.packfile import build_pack_file, sha256_hex
from wassal_content.schemas import SchemaSet, default_schema_set
from wassal_content.source import assemble_pack, read_layout
from wassal_content.validate import validate_pack

__all__ = [
    "DEV_KEPT",
    "FETCH_TIMEOUT",
    "RECORD",
    "RECORD_MAX_BYTES",
    "RELEASE_KEPT",
    "BundleError",
    "check_bundle",
    "check_release",
    "dev_bundle",
    "fetch_record",
    "make_opener",
    "release_bundle",
    "write_bundle",
]

RECORD = "bundled.json"

# The files `bundle dev` leaves alone in its directory. `bundle release` removes the README that
# stands in for a pack until production's first promotion.
DEV_KEPT = frozenset({"README.md"})
RELEASE_KEPT: frozenset[str] = frozenset()

# The release record: B04's promotion reads it with the same cap and timeout.
RECORD_MAX_BYTES = 65536
FETCH_TIMEOUT = 10

# Every stage a release record must name, and those that may pass with a warning
# (B04 contracts/pack-delivery.md, B05).
_STAGES = ("content_rules", "references", "review", "schema", "size", "solver")
_MAY_WARN = frozenset({"size", "solver"})
_CLIENT_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")

Fetcher = Callable[[str], bytes]


class BundleError(ValueError):
    """The inputs can't make a bundle."""


def dev_bundle(sample: Path, golden: Path, schema_set: SchemaSet | None = None) -> dict[str, bytes]:
    """The dev directory's files: the sample built as version 1, and its record."""
    schema_set = schema_set or default_schema_set()
    tree, findings = read_layout(sample, schema_set)
    if findings:
        problems = "\n".join(f"  {f.file}: {f.path}: {f.message}" for f in findings)
        raise BundleError(f"the sample has findings:\n{problems}")
    pack = assemble_pack(tree, GOLDEN_VERSION)
    packed = build_pack_file(canonical_bytes(pack))
    golden_doc = load_json_file(golden)
    try:
        expected = (golden_doc["sha256"], golden_doc["size"])
    except (KeyError, TypeError):
        raise BundleError(f"{golden} has no sha256 and size") from None
    if (sha256_hex(packed), len(packed)) != expected:
        raise BundleError(
            f"the sample's pack file doesn't match {golden}: run `uv run wassal-content golden`"
        )
    return _files(pack, packed, min_client_version=_floor(schema_set, pack), source="sample")


def _floor(schema_set: SchemaSet, pack: Mapping[str, Any]) -> str:
    major = str(pack["schema_version"]).split(".")[0]
    floors = schema_set.min_client_version_by_major
    if major not in floors:
        raise BundleError(f"schema-set.json has no min_client_version for major {major}")
    return floors[major]


def _files(
    pack: Mapping[str, Any],
    packed: bytes,
    *,
    min_client_version: str,
    source: str,
    extra: Mapping[str, Any] | None = None,
) -> dict[str, bytes]:
    name = f"core-{pack['version']}.json.gz"
    record = {
        "pack_id": pack["pack_id"],
        "version": pack["version"],
        "file": name,
        "size": len(packed),
        "sha256": sha256_hex(packed),
        "min_client_version": min_client_version,
        "source": source,
        **(extra or {}),
    }
    return {name: packed, RECORD: canonical_bytes(record)}


def _ours(name: str) -> bool:
    """A file name `bundle` writes, so it may remove a stale one."""
    return name == RECORD or name == "README.md" or name.startswith("core-")


def write_bundle(
    out: Path, files: Mapping[str, bytes], *, keep: frozenset[str]
) -> tuple[list[Path], list[Path]]:
    """Write [files] into [out] and remove stale ones of ours. Returns (written, removed)."""
    out.mkdir(parents=True, exist_ok=True)
    removed = [
        path
        for path in sorted(out.iterdir())
        if path.is_file() and path.name not in files and path.name not in keep and _ours(path.name)
    ]
    for path in removed:
        path.unlink()
    written = []
    # The record last, so a write that fails midway never leaves it naming a missing file.
    for name in sorted(files, key=lambda name: name == RECORD):
        path = out / name
        path.write_bytes(files[name])
        written.append(path)
    return written, removed


def check_bundle(out: Path, files: Mapping[str, bytes], *, keep: frozenset[str]) -> list[str]:
    """One line per difference between [out] and a fresh build."""
    problems = []
    for name in sorted(files):
        path = out / name
        if not path.is_file():
            problems.append(f"{path}: missing")
        elif path.read_bytes() != files[name]:
            problems.append(f"{path}: differs from a fresh build")
    if out.is_dir():
        problems.extend(
            f"{path}: unexpected file"
            + ("" if _ours(path.name) else ", which `bundle` leaves alone")
            for path in sorted(out.iterdir())
            if path.name not in files and path.name not in keep
        )
    return problems


# Release mode.


def release_bundle(
    source: Path,
    packs_url: str,
    *,
    fetch: Fetcher | None = None,
    schema_set: SchemaSet | None = None,
) -> dict[str, bytes]:
    """The release directory's files: the promoted pack, its record and `bundled.json`."""
    schema_set = schema_set or default_schema_set()
    pack, packed = _build_release(source, schema_set)
    base = _packs_base(packs_url)
    url = f"{base}core-{pack['version']}.release.json"
    try:
        record = (fetch or fetch_record)(url)
    except OSError as error:
        raise BundleError(f"the release record is unreachable: {error}") from None
    return _release_files(pack, packed, record, schema_set)


def _packs_base(packs_url: str) -> str:
    """[packs_url] ending in `/`, if it is a plain https URL with a host."""
    try:
        parts = urllib.parse.urlsplit(packs_url)
        plain = (
            parts.scheme == "https"
            and bool(parts.hostname)
            and "@" not in parts.netloc
            and not parts.query
            and not parts.fragment
        )
    except ValueError:
        plain = False
    if not plain:
        raise BundleError(
            f"--packs-url must be an https URL with a host, and no user, query or fragment: "
            f"{packs_url}"
        )
    return packs_url if packs_url.endswith("/") else f"{packs_url}/"


def check_release(source: Path, out: Path, schema_set: SchemaSet | None = None) -> list[str]:
    """One line per difference between [out] and a fresh release build, offline: the
    committed record copy stands in for production's."""
    schema_set = schema_set or default_schema_set()
    tree, findings = read_layout(source, schema_set)
    if tree.meta is None and not findings:
        # No promoted pack yet: only the stand-in README may be there.
        return check_bundle(out, {}, keep=frozenset({"README.md"}))
    pack, packed = _build_release(source, schema_set)
    copy = out / f"core-{pack['version']}.release.json"
    if not copy.is_file():
        return [f"{copy}: missing"]
    try:
        files = _release_files(pack, packed, copy.read_bytes(), schema_set)
    except BundleError as error:
        return [f"{copy}: {line}" for line in str(error).splitlines()]
    return check_bundle(out, files, keep=RELEASE_KEPT)


def _build_release(source: Path, schema_set: SchemaSet | None) -> tuple[dict[str, Any], bytes]:
    schema_set = schema_set or default_schema_set()
    tree, findings = read_layout(source, schema_set)
    if findings:
        raise BundleError(f"{source} has findings:\n{_listed(findings)}")
    if tree.meta is None:
        raise BundleError(f"{source / 'pack.json'} is missing: production has promoted no pack")
    version = int(tree.meta["version"])
    if version < 1:
        raise BundleError(f"{source / 'pack.json'} has version 0: no promoted pack")
    pack = assemble_pack(tree, version)
    packed = build_pack_file(canonical_bytes(pack))
    errors = [
        finding
        for finding in validate_pack(pack, file_size=len(packed), schema_set=schema_set).findings
        if finding.severity == "error"
    ]
    if errors:
        raise BundleError(f"{source} has findings:\n{_listed(errors)}")
    return pack, packed


def _listed(findings: Any) -> str:
    return "\n".join(f"  {f.file}: {f.path}: {f.message}" for f in findings)


def _release_files(
    pack: Mapping[str, Any], packed: bytes, record_bytes: bytes, schema_set: SchemaSet
) -> dict[str, bytes]:
    """The release files for [packed], if production's record agrees with it."""
    if len(record_bytes) > RECORD_MAX_BYTES:
        raise BundleError("the release record is over 64 KiB")
    try:
        record = load_json_bytes(record_bytes)
    except ContentLoadError as error:
        raise BundleError(f"the release record doesn't parse strictly: {error}") from None
    if not isinstance(record, dict):
        raise BundleError("the release record isn't an object")
    problems = [
        f"the release record's {key} is {record.get(key)!r}, the rebuilt file's {expected!r}"
        for key, expected in (
            ("pack_id", pack["pack_id"]),
            ("version", pack["version"]),
            ("sha256", sha256_hex(packed)),
            ("size", len(packed)),
        )
        # `type` too, since True == 1 in Python.
        if type(record.get(key)) is not type(expected) or record.get(key) != expected
    ]
    stages = record.get("stages")
    if not isinstance(stages, dict):
        problems.append("the release record has no stages")
    else:
        problems.extend(
            f"the release record has no {stage} stage" for stage in _STAGES if stage not in stages
        )
        problems.extend(
            f"the release record's {stage} stage is {result!r}"
            for stage, result in sorted(stages.items())
            if not (result == "passed" or (result == "warning" and stage in _MAY_WARN))
        )
    minimum = record.get("min_client_version")
    floor = _floor(schema_set, pack)
    if not isinstance(minimum, str) or not _CLIENT_VERSION.fullmatch(minimum):
        problems.append(f"the release record's min_client_version is {minimum!r}")
    elif _version_key(minimum) < _version_key(floor):
        problems.append(
            f"the release record's min_client_version {minimum} is below the schema floor {floor}"
        )
    if problems:
        raise BundleError("\n".join(problems))
    files = _files(
        pack,
        packed,
        min_client_version=str(minimum),
        source="content_source",
        extra={"release_record_sha256": sha256_hex(record_bytes)},
    )
    files[f"core-{pack['version']}.release.json"] = record_bytes
    return files


def _version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


# The record fetcher: HTTPS only, no redirects, a 64 KiB cap and a 10 s timeout.


class _Opener(Protocol):
    def open(self, fullurl: str, /, *, timeout: float) -> Any: ...


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Turns every redirect into an error: the record is read from the URL given, or not at
    all."""

    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: http.client.HTTPMessage,
        newurl: str,
    ) -> urllib.request.Request | None:
        return None


def make_opener(*handlers: urllib.request.BaseHandler) -> urllib.request.OpenerDirector:
    """An opener that refuses redirects, with [handlers] added (tests replace HTTPS)."""
    return urllib.request.build_opener(_NoRedirect(), *handlers)


def fetch_record(url: str, *, opener: _Opener | None = None) -> bytes:
    """Production's release record at [url]: refused unless it is HTTPS, answers 200 without a
    redirect, and fits in 64 KiB."""
    try:
        scheme = urllib.parse.urlsplit(url).scheme
    except ValueError:
        scheme = ""
    if scheme != "https":
        raise BundleError(f"the release record must be fetched over https, not {url}")
    try:
        with (opener or make_opener()).open(url, timeout=FETCH_TIMEOUT) as response:
            status = getattr(response, "status", 200)
            if status != 200:
                raise BundleError(f"the release record answered {status}")
            data: bytes = response.read(RECORD_MAX_BYTES + 1)
    except BundleError:
        raise
    except urllib.error.HTTPError as error:
        raise BundleError(f"the release record answered {error.code}") from None
    except (OSError, http.client.HTTPException, ValueError) as error:
        # ValueError: urllib's refusal of a malformed URL.
        raise BundleError(f"the release record is unreachable: {error}") from None
    if len(data) > RECORD_MAX_BYTES:
        raise BundleError("the release record is over 64 KiB")
    return data
