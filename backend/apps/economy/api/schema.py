"""The OpenAPI description of the sync envelope's closed objects (contracts/api.md "POST /v1/sync").
Imported by `EconomyConfig.ready`, which registers it with drf-spectacular.

`ClosedSerializer` refuses a key it doesn't list, so its schema says `additionalProperties: false`;
otherwise a client generated from the contract could send extras the server answers with 400.
"""

from __future__ import annotations

from typing import Any

from drf_spectacular.extensions import OpenApiSerializerExtension


class ClosedObjectSchema(OpenApiSerializerExtension):  # type: ignore[no-untyped-call]
    target_class = "apps.economy.api.serializers.ClosedSerializer"
    match_subclasses = True

    def map_serializer(self, auto_schema: Any, direction: str) -> dict[str, Any]:
        schema: dict[str, Any] = auto_schema._map_basic_serializer(self.target, direction)
        schema["additionalProperties"] = False
        return schema
