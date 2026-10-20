"""`GET /v1/content/manifest` (contracts/api.md, FR-029-FR-034).

The payload is cached in Valkey for `CONTENT_MANIFEST_CACHE_SECONDS`, per stated app version.
Publish, promote and minimum-version changes bump a generation number on commit, which retires
every cached payload at once. If the cache is down, the answer comes from the database.
"""

from __future__ import annotations

import logging
import re
from typing import Any

from django.conf import settings
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.db import transaction
from redis.exceptions import RedisError

from apps.accounts.models import User
from apps.content.models import ContentAuditRecord, ContentChannel, ContentPack
from apps.content.models.packs import CLIENT_VERSION_PATTERN, STORED
from apps.content.services import audit, build, files, permissions
from apps.content.services.versioning import PACK_ID

logger = logging.getLogger(__name__)

CACHE_PREFIX = "content:manifest:"
GENERATION_KEY = f"{CACHE_PREFIX}generation"
HEADER = re.compile(r"^([0-9]+)\.([0-9]+)\.([0-9]+)(\+[0-9A-Za-z.-]+)?$")
MAX_HEADER = 64
EMPTY: dict[str, Any] = {"version": 0, "packs": []}
# What a Valkey outage raises through Django's cache: the answer then comes from the database.
CACHE_ERRORS = (RedisError, OSError)

ClientVersion = tuple[int, int, int]


def parse_client_version(header: str | None) -> ClientVersion | None:
    """`1.4.0+57` → (1, 4, 0). A missing or malformed value is "not stated"."""
    if not header or len(header) > MAX_HEADER:
        return None
    match = HEADER.match(header.strip())
    if match is None:
        return None
    return int(match[1]), int(match[2]), int(match[3])


def as_tuple(value: str) -> ClientVersion:
    major, minor, patch = value.split(".")
    return int(major), int(minor), int(patch)


def select_pack(client: ClientVersion | None) -> ContentPack | None:
    """The pack to offer: the current one, or for an older app the newest it can read."""
    channel = ContentChannel.objects.select_related("current").filter(pack_id=PACK_ID).first()
    current = channel.current if channel else None
    if current is None:
        return None
    if client is None or client >= as_tuple(current.min_client_version):
        return current
    older = ContentPack.objects.filter(pack_id=PACK_ID, status__in=sorted(STORED)).only(
        "pack_id", "version", "sha256", "size", "min_client_version"
    )
    for pack in older.order_by("-version"):
        if as_tuple(pack.min_client_version) <= client:
            return pack
    return None


def pack_entry(pack: ContentPack) -> dict[str, Any]:
    version = files.version_of(pack)
    return {
        "pack_id": pack.pack_id,
        "version": version,
        "url": f"{settings.CONTENT_PACKS_PUBLIC_URL}{files.pack_file_name(version)}",
        "sha256": pack.sha256,
        "size": pack.size,
        "min_client_version": pack.min_client_version,
    }


def build_payload(client: ClientVersion | None) -> dict[str, Any]:
    pack = select_pack(client)
    if pack is None:
        return dict(EMPTY)
    entry = pack_entry(pack)
    return {"version": entry["version"], "packs": [entry]}


def _cache_key(client: ClientVersion | None) -> str | None:
    """The key for this app version under the current generation, or None without a cache."""
    generation = cache.get(GENERATION_KEY)
    if generation is None:
        cache.add(GENERATION_KEY, 1, timeout=None)
        generation = cache.get(GENERATION_KEY, 1)
    stated = "none" if client is None else ".".join(map(str, client))
    return f"{CACHE_PREFIX}{generation}:{stated}"


def manifest_payload(header: str | None) -> dict[str, Any]:
    """The manifest for the `X-Client-Version` header, from the cache when it can."""
    client = parse_client_version(header)
    seconds = settings.CONTENT_MANIFEST_CACHE_SECONDS
    if seconds <= 0:
        return build_payload(client)
    try:
        key = _cache_key(client)
        cached = cache.get(key)
    except CACHE_ERRORS:
        logger.warning("manifest cache unavailable, answering from the database")
        return build_payload(client)
    if cached is not None:
        return dict(cached)
    payload = build_payload(client)
    try:
        cache.set(key, payload, timeout=seconds)
    except CACHE_ERRORS:
        logger.warning("manifest cache unavailable, not storing")
    return payload


def invalidate() -> None:
    """Retire every cached manifest. Called on commit of publish, promote and minimum changes."""
    try:
        try:
            cache.incr(GENERATION_KEY)
        except ValueError:  # no generation yet: nothing cached under one either
            cache.add(GENERATION_KEY, 1, timeout=None)
    except CACHE_ERRORS:
        # Cached answers then live out their 30 s, which FR-031's minute allows.
        logger.warning("manifest cache unavailable, not invalidated")


# -- the minimum app version (FR-032) ------------------------------------------------------------

CHANGE_PERMISSION = "content.change_min_client_version"
MIN_VERSION = re.compile(CLIENT_VERSION_PATTERN)


def floor_for(pack: ContentPack) -> str:
    return build.min_client_floor(pack.schema_version)


def change_min_client_version(pack: ContentPack, value: str, actor: User | None) -> ContentPack:
    """Raise or lower a stored pack's minimum app version, never below its schema major's floor.

    Both roles may (contracts/admin.md). The change and every refusal are audited.
    """
    action = ContentAuditRecord.Action.MIN_CLIENT_VERSION_CHANGE
    old = pack.min_client_version
    try:
        permissions.require(actor, CHANGE_PERMISSION)
        if pack.status not in STORED:
            raise ValidationError("Only a published or retired pack's minimum can change.")
        if not MIN_VERSION.match(value):
            raise ValidationError("Use MAJOR.MINOR.PATCH, such as 1.2.0.")
        floor = floor_for(pack)
        if as_tuple(value) < as_tuple(floor):
            raise ValidationError(f"Schema {pack.schema_version} packs need at least {floor}.")
    except Exception as error:
        audit.record(
            action,
            ContentAuditRecord.Outcome.FAILED,
            _name(actor),
            pack,
            {"old": old, "new": value, "reason": _reason(error)},
        )
        raise
    with transaction.atomic():
        pack.min_client_version = value
        pack.save(update_fields=["min_client_version", "updated_at"])
        audit.record(
            action,
            ContentAuditRecord.Outcome.SUCCEEDED,
            _name(actor),
            pack,
            {"old": old, "new": value},
        )
        transaction.on_commit(invalidate)
    return pack


def _name(actor: User | None) -> str:
    return actor.username if actor is not None else ""


def _reason(error: Exception) -> str:
    if isinstance(error, ValidationError):
        return "; ".join(error.messages)
    return str(error)
