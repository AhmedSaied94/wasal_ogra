"""The OpenAPI description of player authentication: the `bearerAuth` scheme (B02 contracts/api.md
"OpenAPI"). Imported by `AccountsConfig.ready`, which registers it with drf-spectacular."""

from __future__ import annotations

from typing import Any

from drf_spectacular.extensions import OpenApiAuthenticationExtension


class PlayerAuthenticationScheme(OpenApiAuthenticationExtension):  # type: ignore[no-untyped-call]
    target_class = "apps.accounts.authentication.PlayerAuthentication"
    name = "bearerAuth"

    def get_security_definition(self, auto_schema: Any) -> dict[str, str]:
        return {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}
