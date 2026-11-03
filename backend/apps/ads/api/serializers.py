"""Shapes of the ads endpoints, for the OpenAPI schema (B07 contracts/api.md). The views answer
with plain dicts."""

from __future__ import annotations

from typing import Any

from rest_framework import serializers

from apps.ads.models import AdReward
from apps.economy.api.serializers import WalletSerializer

# Named in SPECTACULAR_SETTINGS["ENUM_NAME_OVERRIDES"], so they never rename sync's enums.
REWARD_STATUSES = ("granted", "refused")
REFUSALS = (
    str(AdReward.Outcome.CAP_REACHED),
    str(AdReward.Outcome.NOT_SERVER_PLACEMENT),
    str(AdReward.Outcome.EXPIRED),
)


class SsvAnswerSerializer(serializers.Serializer[dict[str, Any]]):
    """Always `{}`: the answer never says what happened."""


class RewardSerializer(serializers.Serializer[dict[str, Any]]):
    status = serializers.ChoiceField(choices=REWARD_STATUSES)
    jenehat = serializers.IntegerField(min_value=0, required=False, help_text="When granted.")
    bonat = serializers.IntegerField(min_value=0, required=False, help_text="When granted.")
    granted_at = serializers.DateTimeField(required=False, help_text="When granted.")
    wallet = WalletSerializer(required=False, help_text="When granted: recounted to now.")
    reason = serializers.ChoiceField(choices=REFUSALS, required=False, help_text="When refused.")
