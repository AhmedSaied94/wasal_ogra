"""Request and response shapes of `POST /v1/sync`, `GET /v1/bootstrap` and `GET /v1/state`
(contracts/api.md).

The sync envelope is validated here, strictly: closed objects, integers that are integers, a
canonical UUIDv7 and a UTC time. A bad envelope can't be attributed to one operation, so it refuses
the whole batch. Each operation's payload is checked later, by the engine, and a bad one rejects
only that operation (contracts/operations.md). Responses are built as plain dicts by the views,
and the other serializers here describe them for the OpenAPI schema.
"""

from __future__ import annotations

import re
import uuid
from datetime import UTC, datetime
from typing import Any

from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework.settings import api_settings

from apps.economy.api import messages
from apps.economy.services.sync import MAX_OPS, REASONS

# The canonical lowercase form of a version-7 UUID with the RFC 4122 variant.
TXN_ID_PATTERN = r"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
TXN_ID = re.compile(TXN_ID_PATTERN)
UTC_PATTERN = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$"
UTC_TIME = re.compile(UTC_PATTERN)
OP_TYPE_MAX = 40
OP_TYPE_PATTERN = rf"^[a-z][a-z0-9_]{{0,{OP_TYPE_MAX - 1}}}$"


class ClosedSerializer(serializers.Serializer[dict[str, Any]]):
    """A JSON object with exactly these keys: an unknown key is an error named after it."""

    def to_internal_value(self, data: Any) -> dict[str, Any]:
        if not isinstance(data, dict):
            # As DRF's own: under the non-field key, so the error has a name at any depth.
            raise serializers.ValidationError(
                {api_settings.NON_FIELD_ERRORS_KEY: [messages.OBJECT]}
            )
        unknown = sorted(set(data) - set(self.fields))
        if unknown:
            raise serializers.ValidationError({key: [messages.UNKNOWN] for key in unknown})
        cleaned: dict[str, Any] = super().to_internal_value(data)
        return cleaned


@extend_schema_field({"type": "integer", "minimum": 0})
class StateVersionField(serializers.Field[int, int, int, Any]):
    default_error_messages = messages.fixed(messages.STATE_VERSION)

    def to_internal_value(self, data: object) -> int:
        if type(data) is not int or data < 0:
            self.fail("invalid")
        return data

    def to_representation(self, value: int) -> int:
        return value


@extend_schema_field({"type": "string", "format": "uuid", "pattern": TXN_ID_PATTERN})
class TxnIdField(serializers.Field[uuid.UUID, str, str, Any]):
    default_error_messages = messages.fixed(messages.TXN_ID)

    def to_internal_value(self, data: object) -> uuid.UUID:
        if not isinstance(data, str) or not TXN_ID.fullmatch(data):
            self.fail("invalid")
        return uuid.UUID(data)

    def to_representation(self, value: uuid.UUID) -> str:
        return str(value)


@extend_schema_field({"type": "string", "pattern": OP_TYPE_PATTERN})
class OpTypeField(serializers.Field[str, str, str, Any]):
    """Any short name in lowercase letters, digits and `_`: a type this version doesn't know is
    that operation's `unknown_op_type`, not an error of the batch. Anything else can't be a type,
    and isn't stored."""

    default_error_messages = messages.fixed(messages.OP_TYPE)

    def to_internal_value(self, data: object) -> str:
        if not isinstance(data, str) or not re.fullmatch(OP_TYPE_PATTERN, data):
            self.fail("invalid")
        return data

    def to_representation(self, value: str) -> str:
        return value


@extend_schema_field({"type": "string", "format": "date-time", "pattern": UTC_PATTERN})
class UtcTimeField(serializers.Field[datetime, str, str, Any]):
    default_error_messages = messages.fixed(messages.OCCURRED_AT)

    def to_internal_value(self, data: object) -> datetime:
        if not isinstance(data, str) or not UTC_TIME.fullmatch(data):
            self.fail("invalid")
        try:
            return datetime.fromisoformat(data).astimezone(UTC)
        except ValueError:
            self.fail("invalid")

    def to_representation(self, value: datetime) -> str:
        return value.isoformat()


@extend_schema_field(
    {
        "type": "object",
        "additionalProperties": True,
        "description": (
            "The operation's payload: a closed object whose keys depend on op_type "
            "(contracts/operations.md). A payload of the wrong shape rejects that operation "
            "with validation_error; the batch goes on."
        ),
    }
)
class PayloadField(serializers.Field[dict[str, Any], dict[str, Any], dict[str, Any], Any]):
    default_error_messages = messages.fixed(messages.PAYLOAD)

    def to_internal_value(self, data: object) -> dict[str, Any]:
        if not isinstance(data, dict):
            self.fail("invalid")
        return data

    def to_representation(self, value: dict[str, Any]) -> dict[str, Any]:
        return value


class OpSerializer(ClosedSerializer):
    """One operation's envelope. A malformed envelope refuses the whole batch."""

    client_txn_id = TxnIdField()
    op_type = OpTypeField()
    occurred_at = UtcTimeField()
    payload = PayloadField()


class SyncSerializer(ClosedSerializer):
    """A batch of up to 100 operations, applied in array order, and the state version the phone
    last saw."""

    base_state_version = StateVersionField()
    ops = serializers.ListField(
        child=OpSerializer(), max_length=MAX_OPS, error_messages=messages.fixed(messages.OPS)
    )


# -- responses (for the schema) --------------------------------------------------------------------


class WalletSerializer(serializers.Serializer[dict[str, Any]]):
    jenehat = serializers.IntegerField(min_value=0)
    bonat = serializers.IntegerField(min_value=0)
    fuel = serializers.IntegerField(
        min_value=0, help_text="Liters at the server's time, regenerated."
    )
    fuel_max = serializers.IntegerField(min_value=1)
    fuel_updated_at = serializers.DateTimeField(
        help_text="The countdown's anchor (M05's countedFrom)."
    )
    fuel_unlimited_until = serializers.DateTimeField(allow_null=True)


class OpResultSerializer(serializers.Serializer[dict[str, Any]]):
    client_txn_id = serializers.UUIDField()
    status = serializers.ChoiceField(choices=("accepted", "rejected"))
    reason = serializers.ChoiceField(
        choices=REASONS,
        required=False,
        help_text="Only when rejected. A phone treats a reason it doesn't know as a rejection.",
    )
    granted = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        help_text="What the server granted that the phone did not propose (operations.md).",
    )
    details = serializers.DictField(
        required=False, help_text="For validation_error: the payload's field, as details.field."
    )


class SyncResultSerializer(serializers.Serializer[dict[str, Any]]):
    state_version = serializers.IntegerField(min_value=0)
    state_stale = serializers.BooleanField()
    results = OpResultSerializer(many=True)
    wallet = WalletSerializer()


class BootstrapPlayerSerializer(serializers.Serializer[dict[str, Any]]):
    player_id = serializers.UUIDField()
    display_name = serializers.CharField(allow_blank=True)
    driver_level = serializers.IntegerField(min_value=1)
    country = serializers.CharField(allow_blank=True)
    providers = serializers.ListField(child=serializers.ChoiceField(choices=("google",)))


class EntitlementFlagsSerializer(serializers.Serializer[dict[str, Any]]):
    no_interstitials = serializers.BooleanField()
    fuel_max_bonus = serializers.IntegerField(min_value=0)


class EntitlementsSerializer(serializers.Serializer[dict[str, Any]]):
    remove_ads = serializers.BooleanField()
    subscription = serializers.DictField(allow_null=True, help_text="null until B06.")
    season_passes = serializers.ListField(
        child=serializers.CharField(), help_text="Empty until B12."
    )
    flags = EntitlementFlagsSerializer()


class ContentRefSerializer(serializers.Serializer[dict[str, Any]]):
    version = serializers.IntegerField(
        min_value=1, allow_null=True, help_text="The current core pack; null before the first."
    )
    manifest_url = serializers.CharField()


class ClientBlockSerializer(serializers.Serializer[dict[str, Any]]):
    min_version = serializers.CharField()
    latest_version = serializers.CharField()
    force_update = serializers.BooleanField(
        help_text="X-Client-Version is below min_version. The answer is still complete."
    )


class DailySerializer(serializers.Serializer[dict[str, Any]]):
    game_date = serializers.DateField(help_text="The Africa/Cairo calendar day.")
    challenge_available = serializers.BooleanField(help_text="false until B08.")
    reward_claimable = serializers.BooleanField(help_text="false until B08.")


class ComebackSerializer(serializers.Serializer[dict[str, Any]]):
    claimable = serializers.BooleanField()


class BootstrapSerializer(serializers.Serializer[dict[str, Any]]):
    server_time = serializers.DateTimeField()
    player = BootstrapPlayerSerializer()
    wallet = WalletSerializer()
    entitlements = EntitlementsSerializer()
    state_version = serializers.IntegerField(min_value=0)
    content = ContentRefSerializer()
    client = ClientBlockSerializer()
    daily = DailySerializer()
    comeback = ComebackSerializer()


class StatePlayerSerializer(serializers.Serializer[dict[str, Any]]):
    display_name = serializers.CharField(allow_blank=True)
    driver_level = serializers.IntegerField(min_value=1)
    settings = serializers.DictField(help_text="What settings_update stored.")


class InventorySerializer(serializers.Serializer[dict[str, Any]]):
    change_bag = serializers.IntegerField(min_value=0)
    wake_all = serializers.IntegerField(min_value=0)
    ledger_peek = serializers.IntegerField(min_value=0)
    traffic_jam = serializers.IntegerField(min_value=0)


class OwnedSerializer(serializers.Serializer[dict[str, Any]]):
    kind = serializers.ChoiceField(choices=("vehicle", "upgrade", "cosmetic", "item", "chapter"))
    sku_id = serializers.CharField(help_text="May name an id the active pack lacks: skip it.")
    variant = serializers.CharField(allow_blank=True)


class TripStandingSerializer(serializers.Serializer[dict[str, Any]]):
    trip_id = serializers.CharField(help_text="May name an id the active pack lacks: skip it.")
    best_stars = serializers.IntegerField(min_value=0, max_value=3)
    best_time_ms = serializers.IntegerField(min_value=0, allow_null=True)
    plays = serializers.IntegerField(min_value=0)


class OpenTripSerializer(serializers.Serializer[dict[str, Any]]):
    start_txn = serializers.UUIDField()
    trip_id = serializers.CharField()
    content_version = serializers.IntegerField(min_value=1)
    revived = serializers.BooleanField()
    traffic_jam_ads = serializers.IntegerField(min_value=0)


class LastResultSerializer(serializers.Serializer[dict[str, Any]]):
    start_txn = serializers.UUIDField()
    outcome = serializers.ChoiceField(choices=("finished", "failed", "abandoned"))
    earnings_jenehat = serializers.IntegerField(min_value=0)
    doubled = serializers.BooleanField()


class ChapterStateSerializer(serializers.Serializer[dict[str, Any]]):
    chapter_id = serializers.CharField()
    status = serializers.ChoiceField(choices=("open", "completed"))
    scenes_seen = serializers.ListField(child=serializers.CharField())


class StorySerializer(serializers.Serializer[dict[str, Any]]):
    chapters = ChapterStateSerializer(many=True)
    requests_claimed = serializers.ListField(child=serializers.CharField())


class GrantsSerializer(serializers.Serializer[dict[str, Any]]):
    tutorial = serializers.BooleanField()


class StatsSerializer(serializers.Serializer[dict[str, Any]]):
    trips_played = serializers.IntegerField(
        min_value=0, help_text="Every accepted result, abandoned ones too."
    )
    stars_total = serializers.IntegerField(min_value=0, help_text="The sum of best_stars.")
    longest_streak = serializers.IntegerField(min_value=0, help_text="0 until B08.")


class StateSerializer(serializers.Serializer[dict[str, Any]]):
    state_version = serializers.IntegerField(min_value=0)
    server_time = serializers.DateTimeField()
    player = StatePlayerSerializer()
    wallet = WalletSerializer()
    inventory = InventorySerializer()
    ownership = OwnedSerializer(many=True)
    trips = TripStandingSerializer(many=True)
    open_trip = OpenTripSerializer(allow_null=True)
    last_result = LastResultSerializer(allow_null=True)
    story = StorySerializer()
    grants = GrantsSerializer()
    stats = StatsSerializer()
    comeback = ComebackSerializer()
