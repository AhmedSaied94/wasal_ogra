"""Request and response shapes of the auth endpoints (B02 contracts/api.md).

Requests are validated here. Responses are built as plain dicts by the views, and these
serializers describe them for the OpenAPI schema.
"""

from __future__ import annotations

import re
import uuid
from typing import Any

from django.conf import settings
from django.core.validators import ProhibitNullCharactersValidator
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from apps.accounts.api import messages
from apps.accounts.tokens import MAX_TOKEN_LENGTH
from apps.common.client import PLATFORMS

# The canonical v4 form, any letter case (contracts/api.md): 8-4-4-4-12, version 4, RFC variant.
INSTALL_ID_PATTERN = (
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
INSTALL_ID = re.compile(INSTALL_ID_PATTERN)
LOCALE = r"^[a-z]{2,3}(-[A-Z]{2})?$"
PROVIDERS = ("google",)
RESOLUTIONS = ("switch_to_existing", "keep_current")


@extend_schema_field({"type": "string", "format": "uuid", "pattern": INSTALL_ID_PATTERN})
class InstallIdField(serializers.Field[uuid.UUID, str, str, Any]):
    """A version-4 UUID string, read as lowercase. Its error never repeats the value (FR-002)."""

    default_error_messages = messages.fixed(messages.INSTALL_ID)

    def to_internal_value(self, data: object) -> uuid.UUID:
        if not isinstance(data, str) or not INSTALL_ID.fullmatch(data):
            self.fail("invalid")
        return uuid.UUID(data.lower())

    def to_representation(self, value: uuid.UUID) -> str:
        return str(value)


class TokenField(serializers.CharField):
    """A credential of 1 to 4096 characters. Its characters are the signature check's business: a
    string the schema allows that isn't a token is a 401 or a 422 (contracts/api.md), so a NUL
    isn't refused here as a 400. Its error never repeats the value."""

    def __init__(self) -> None:
        super().__init__(
            max_length=MAX_TOKEN_LENGTH,
            trim_whitespace=False,
            error_messages=messages.fixed(messages.TOKEN),
        )
        self.validators = [
            v for v in self.validators if not isinstance(v, ProhibitNullCharactersValidator)
        ]


class AnonymousSerializer(serializers.Serializer[None]):
    install_id = InstallIdField(error_messages=messages.fixed(messages.INSTALL_ID))
    platform = serializers.ChoiceField(
        choices=PLATFORMS, error_messages=messages.fixed(messages.PLATFORM)
    )
    locale = serializers.RegexField(
        LOCALE, max_length=16, error_messages=messages.fixed(messages.LOCALE)
    )


class RefreshSerializer(serializers.Serializer[None]):
    refresh = TokenField()


class LinkSerializer(serializers.Serializer[None]):
    provider = serializers.ChoiceField(
        choices=PROVIDERS, error_messages=messages.fixed(messages.PROVIDER)
    )
    id_token = TokenField()
    resolve = serializers.ChoiceField(
        choices=RESOLUTIONS, required=False, error_messages=messages.fixed(messages.RESOLVE)
    )
    existing_player_id = serializers.UUIDField(
        required=False, error_messages=messages.fixed(messages.PLAYER_ID)
    )

    def validate_provider(self, value: str) -> str:
        # An environment with no Google client id can't verify Google tokens (research R6).
        if value == "google" and not settings.GOOGLE_OAUTH_CLIENT_IDS:
            raise serializers.ValidationError(messages.PROVIDER_DISABLED)
        return value

    def validate(self, attrs: dict[str, Any]) -> dict[str, Any]:
        if ("resolve" in attrs) != ("existing_player_id" in attrs):
            raise serializers.ValidationError(messages.RESOLVE_PAIR)
        return attrs


# -- responses ------------------------------------------------------------------------------------


class TokenPairSerializer(serializers.Serializer[None]):
    player_id = serializers.UUIDField()
    access = serializers.CharField()
    refresh = serializers.CharField()
    access_expires_in = serializers.IntegerField(help_text="Seconds until `access` expires: 900.")
    providers = serializers.ListField(child=serializers.ChoiceField(choices=PROVIDERS))


class AnonymousTokenPairSerializer(TokenPairSerializer):
    created = serializers.BooleanField()


class LinkResultSerializer(serializers.Serializer[None]):
    """A link's answer. After `switch_to_existing` it is the existing player's `TokenPair`, so the
    token fields are there too."""

    player_id = serializers.UUIDField()
    providers = serializers.ListField(child=serializers.ChoiceField(choices=PROVIDERS))
    access = serializers.CharField(required=False, help_text="After switch_to_existing only.")
    refresh = serializers.CharField(required=False, help_text="After switch_to_existing only.")
    access_expires_in = serializers.IntegerField(
        required=False, help_text="After switch_to_existing only: 900."
    )


class ConflictSummarySerializer(serializers.Serializer[None]):
    driver_level = serializers.IntegerField()
    chapter_id = serializers.CharField()
    bonat = serializers.IntegerField()


class ExistingConflictSummarySerializer(ConflictSummarySerializer):
    player_id = serializers.UUIDField()


class ConflictDetailsSerializer(serializers.Serializer[None]):
    """`details` of a 409: both summaries for `provider_in_use`, the provider for
    `provider_already_linked`."""

    current = ConflictSummarySerializer(required=False)
    existing = ExistingConflictSummarySerializer(required=False)
    provider = serializers.ChoiceField(choices=PROVIDERS, required=False)


class ConflictErrorSerializer(serializers.Serializer[None]):
    code = serializers.ChoiceField(choices=["provider_in_use", "provider_already_linked"])
    message = serializers.CharField()
    details = ConflictDetailsSerializer()


class ConflictEnvelopeSerializer(serializers.Serializer[None]):
    error = ConflictErrorSerializer()
