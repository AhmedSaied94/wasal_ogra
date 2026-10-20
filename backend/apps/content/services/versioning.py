"""Version numbers come only from the source (contracts/pack-delivery.md "Version numbers", R7).

The next version is `max(last assigned, imported content/source version, production's floor) + 1`.
The floor file is read before the row lock, so a slow production never holds it. Any answer but a
valid floor file refuses the build, and nothing is assigned.
"""

from __future__ import annotations

from django.conf import settings
from django.db import transaction
from wassal_content.loader import ContentLoadError, load_json_bytes

from apps.content.models import ContentChannel
from apps.content.services import http

PACK_ID = "core"
FLOOR_FILE = "core.floor.json"
MAX_FLOOR_BYTES = 1024


class VersionFloorUnavailable(Exception):
    code = "version_floor_unavailable"

    def __init__(self, why: str) -> None:
        super().__init__(f"{self.code}: {why}")


def read_floor() -> int:
    """Production's highest stored version, or 0 without a floor URL (dev, test)."""
    base = settings.CONTENT_VERSION_FLOOR_URL
    if not base:
        return 0
    try:
        body = http.fetch(f"{base}{FLOOR_FILE}", max_bytes=MAX_FLOOR_BYTES)
    except http.FetchError as error:
        raise VersionFloorUnavailable(str(error)) from None
    try:
        document = load_json_bytes(body)
    except ContentLoadError:
        raise VersionFloorUnavailable("the floor file doesn't parse") from None
    if not isinstance(document, dict) or document.get("pack_id") != PACK_ID:
        raise VersionFloorUnavailable("the floor file isn't core's")
    floor = document.get("max_version")
    if type(floor) is not int or floor < 0:
        raise VersionFloorUnavailable("max_version isn't an integer of at least 0")
    return floor


def peek_next_version() -> int:
    """The version the next build would get, without assigning it (`content_build --dry-run`)."""
    floor = read_floor()
    channel = ContentChannel.objects.get_or_create(pack_id=PACK_ID)[0]
    return max(channel.last_assigned_version, channel.imported_version, floor) + 1


def next_version() -> int:
    """Assign the next version under a row lock, so concurrent builds never share one."""
    floor = read_floor()
    with transaction.atomic():
        channel = ContentChannel.objects.select_for_update().get_or_create(pack_id=PACK_ID)[0]
        version = max(channel.last_assigned_version, channel.imported_version, floor) + 1
        channel.last_assigned_version = version
        channel.save(update_fields=["last_assigned_version", "updated_at"])
    return version
