"""Export content in the `content/source` layout (contracts/content-source.md "Export").

The current content is exported with `pack.json` `version: 0`. A published pack is exported from
its stored file, so it is exactly what was built. Both zips are deterministic: sorted entries, a
fixed timestamp and fixed permissions.
"""

from __future__ import annotations

import io
import zipfile
from collections.abc import Mapping
from typing import Any

from django.conf import settings
from wassal_content.loader import load_json_bytes
from wassal_content.packfile import decompress_capped
from wassal_content.schemas import default_schema_set
from wassal_content.source import assemble_pack, pack_to_files

from apps.accounts.models import User
from apps.content.models import ContentPack
from apps.content.services import permissions, snapshot

MiB = 1024 * 1024
MAX_PACK_JSON = 32 * MiB  # contracts/pack-delivery.md, promotion step 5
ZIP_DATE = (1980, 1, 1, 0, 0, 0)


def schema_version() -> str:
    """`MAJOR.MINOR` of the packaged schema set."""
    return str(default_schema_set().meta["version"])


def current_files(actor: User | None) -> dict[str, bytes]:
    """The current content's layout files. Needs `export_content`, on `source` only."""
    permissions.require(actor, "content.export_content")
    permissions.require_role(permissions.SOURCE)
    parts = snapshot.snapshot(schema_version()).tree
    return pack_to_files(assemble_pack(parts, 0), 0)


def pack_files(pack: ContentPack, actor: User | None) -> dict[str, bytes]:
    """A published pack's layout files, read back from its stored file. Any active staff."""
    permissions.require_staff(actor)
    stored = stored_pack(pack)
    return pack_to_files(stored, int(stored["version"]))


def stored_pack(pack: ContentPack) -> dict[str, Any]:
    """The pack's JSON, decompressed from its stored file with a cap."""
    data: Mapping[str, Any] = load_json_bytes(
        decompress_capped(bytes(pack.file), max_bytes=MAX_PACK_JSON)
    )
    return dict(data)


def zip_bytes(files: Mapping[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=ZIP_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, files[name])
    return buffer.getvalue()


def export_current(actor: User | None) -> bytes:
    return zip_bytes(current_files(actor))


def export_pack(pack: ContentPack, actor: User | None) -> bytes:
    return zip_bytes(pack_files(pack, actor))


def zip_name(version: int | None = None) -> str:
    env = settings.WASSAL_ENV
    return f"content-{env}-current.zip" if version is None else f"content-{env}-core-{version}.zip"
