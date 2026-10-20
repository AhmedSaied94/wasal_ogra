"""Pack files on the host (contracts/pack-delivery.md, research R5).

Only the worker writes here. Pack files and release records are create-only and never deleted or
overwritten. The floor file (production only) is the one file that is replaced, and its value
never goes down.
"""

from __future__ import annotations

import fcntl
import hashlib
import logging
import os
import tempfile
from contextlib import suppress
from dataclasses import dataclass, field
from pathlib import Path

from django.conf import settings
from django.db.models import Max
from wassal_content.canonical import canonical_bytes
from wassal_content.loader import ContentLoadError, load_json_bytes

from apps.content.models import ContentPack
from apps.content.models.packs import STORED
from apps.content.services import permissions
from apps.content.services.versioning import FLOOR_FILE, MAX_FLOOR_BYTES, PACK_ID

logger = logging.getLogger(__name__)

FILE_MODE = 0o644


class FileConflict(Exception):
    """A create-only name already holds different bytes. The file is left as it is."""

    def __init__(self, name: str) -> None:
        self.name = name
        super().__init__(f"{name} already exists with different bytes")


def packs_dir() -> Path:
    return Path(settings.CONTENT_PACKS_DIR)


def version_of(pack: ContentPack) -> int:
    """A stored or validated pack's version, which only a queued build lacks."""
    if pack.version is None:
        raise ValueError(f"{pack} has no version yet")
    return pack.version


def pack_file_name(version: int) -> str:
    return f"{PACK_ID}-{version}.json.gz"


def release_file_name(version: int) -> str:
    return f"{PACK_ID}-{version}.release.json"


def sha256_of(path: Path) -> str:
    """The file's sha256, read back from disk."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(64 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fsync_dir(directory: Path) -> None:
    fd = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _temp_copy(directory: Path, data: bytes) -> Path:
    """`data` in a hidden temporary file of `directory`, synced, mode 0644."""
    fd, name = tempfile.mkstemp(dir=directory, prefix=".tmp-")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, FILE_MODE)
    except BaseException:
        with suppress(OSError):
            os.unlink(name)
        raise
    return Path(name)


def write_create_only(path: Path, data: bytes) -> bool:
    """Create `path` holding `data`. True if written, False if it already held the same bytes.

    The bytes go to a temporary file first, which is then linked to its name. The link fails if
    the name exists, so a crash never leaves a partial file under a pack's name, and a retry sees
    either nothing or the complete file.
    """
    temp = _temp_copy(path.parent, data)
    try:
        os.link(temp, path)
    except FileExistsError:
        if path.read_bytes() == data:
            return False
        logger.error("pack file conflict", extra={"file": path.name})
        raise FileConflict(path.name) from None
    finally:
        with suppress(OSError):
            temp.unlink()
    fsync_dir(path.parent)
    return True


# -- the floor file (production only) -----------------------------------------------------------


def floor_path() -> Path:
    return packs_dir() / FLOOR_FILE


def read_floor_file() -> int | None:
    """The floor file's `max_version`, or None when it is missing or doesn't parse."""
    path = floor_path()
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        return None
    try:
        document = load_json_bytes(data) if len(data) <= MAX_FLOOR_BYTES else None
    except ContentLoadError:
        document = None
    value = document.get("max_version") if isinstance(document, dict) else None
    if (
        not isinstance(document, dict)
        or document.get("pack_id") != PACK_ID
        or type(value) is not int
        or value < 0
    ):
        logger.error("the floor file doesn't parse", extra={"file": FLOOR_FILE})
        return None
    return value


def highest_stored_version() -> int:
    stored = ContentPack.objects.filter(pack_id=PACK_ID, status__in=sorted(STORED))
    return stored.aggregate(highest=Max("version"))["highest"] or 0


def write_floor(version: int) -> int:
    """Raise the floor file to `version`, never lowering it, and return its value.

    A floor file that doesn't parse is replaced from the database: by `version` or the highest
    stored version, whichever is higher.
    """
    if permissions.role() != permissions.TARGET:
        raise RuntimeError("only production writes the floor file")
    # Two workers (a promotion and the daily sync) must not each read the old value and then
    # write theirs in the wrong order, which would lower the floor.
    # The lock is on the directory itself, so it leaves no extra file next to the packs.
    fd = os.open(packs_dir(), os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        return _raise_floor(version)
    finally:
        os.close(fd)  # also releases the lock


def _raise_floor(version: int) -> int:
    current = read_floor_file()
    if current is None:
        current = highest_stored_version()
    elif current >= version:
        return current
    value = max(current, version)
    path = floor_path()
    temp = _temp_copy(path.parent, canonical_bytes({"max_version": value, "pack_id": PACK_ID}))
    try:
        os.replace(temp, path)
    except BaseException:
        with suppress(OSError):
            temp.unlink()
        raise
    fsync_dir(path.parent)
    return value


def ensure_floor() -> None:
    """On production's worker start: create a missing floor file from the stored packs, or 0."""
    if permissions.role() == permissions.TARGET and not floor_path().exists():
        write_floor(highest_stored_version())


# -- keeping files and records together ---------------------------------------------------------


@dataclass
class SyncResult:
    written: list[str] = field(default_factory=list)
    verified: int = 0
    problems: list[str] = field(default_factory=list)


def sync_files(*, verify: bool) -> SyncResult:
    """Write every stored pack's missing files from the database, create-only.

    With `verify`, present files are hashed, and a mismatch is an error event; the file is not
    touched. On production the floor file is then raised to the highest stored version.
    """
    result = SyncResult()
    directory = packs_dir()
    stored = ContentPack.objects.filter(pack_id=PACK_ID, status__in=sorted(STORED))
    for pack in stored.order_by("version").iterator():
        version = version_of(pack)
        expected = (
            (pack_file_name(version), bytes(pack.file), pack.sha256),
            (release_file_name(version), bytes(pack.release_file), pack.release_sha256),
        )
        for name, data, sha256 in expected:
            path = directory / name
            if not path.exists():
                _restore(path, data, sha256, result)
            elif verify:
                if sha256_of(path) == sha256:
                    result.verified += 1
                else:
                    logger.error("pack file doesn't match its record", extra={"file": name})
                    result.problems.append(f"{name} doesn't match its record")
    if permissions.role() == permissions.TARGET:
        write_floor(highest_stored_version())
    return result


def _restore(path: Path, data: bytes, sha256: str, result: SyncResult) -> None:
    if hashlib.sha256(data).hexdigest() != sha256:
        logger.error("a stored pack doesn't match its record", extra={"file": path.name})
        result.problems.append(f"{path.name}: the database copy doesn't match its record")
        return
    try:
        if write_create_only(path, data):
            result.written.append(path.name)
    except FileConflict as conflict:
        result.problems.append(str(conflict))
