"""The client headers: `X-Client-Version` and `X-Platform` (B02 research R10, FR-034).

The manifest reads the version leniently (B04: missing or malformed means "not stated"). Player
endpoints require both headers through `apps.common.permissions.ClientHeaders`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import TYPE_CHECKING

from rest_framework.exceptions import ValidationError

if TYPE_CHECKING:
    from rest_framework.request import Request

HEADER = re.compile(r"^([0-9]+)\.([0-9]+)\.([0-9]+)(\+[0-9A-Za-z.-]+)?$")
MAX_HEADER = 64
# What a player's and a device's `client_version` columns hold (B02 data-model.md).
MAX_STORED_VERSION = 32
PLATFORMS = ("android", "ios")

VERSION_HEADER = "X-Client-Version"
PLATFORM_HEADER = "X-Platform"
REQUIRED_MESSAGE = "This header is required."
VERSION_MESSAGE = "Must be MAJOR.MINOR.PATCH with an optional +BUILD."
PLATFORM_MESSAGE = "Must be android or ios."

ClientVersion = tuple[int, int, int]


@dataclass(frozen=True)
class ClientInfo:
    """The two headers of a player request, checked."""

    version: str
    platform: str


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


def parse_platform(value: str | None) -> str | None:
    return value if value in PLATFORMS else None


def client_info(request: Request) -> ClientInfo:
    """Both headers, or `400 validation_error` naming each bad one. Never echoes a value."""
    version = request.headers.get(VERSION_HEADER)
    platform = request.headers.get(PLATFORM_HEADER)
    errors: dict[str, list[str]] = {}
    if not version:
        errors[VERSION_HEADER] = [REQUIRED_MESSAGE]
    elif len(version) > MAX_STORED_VERSION or parse_client_version(version) is None:
        errors[VERSION_HEADER] = [VERSION_MESSAGE]
    if not platform:
        errors[PLATFORM_HEADER] = [REQUIRED_MESSAGE]
    elif parse_platform(platform) is None:
        errors[PLATFORM_HEADER] = [PLATFORM_MESSAGE]
    if errors or version is None or platform is None:
        raise ValidationError(errors)
    return ClientInfo(version=version.strip(), platform=platform)
