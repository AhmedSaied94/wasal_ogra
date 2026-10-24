"""Player authentication for every API endpoint (B02 research R1, R11, FR-013, FR-014).

An access token becomes `request.user` (the `Player`) and `request.auth` (the token). The player's
status is read on every request, so a deletion takes effect at once. Staff never authenticate the
API: this class resolves `Player` rows only, and no session or basic authentication is installed.
"""

from __future__ import annotations

import uuid
from typing import TYPE_CHECKING

from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import ExpiredTokenError, TokenError

from apps.accounts.models import Player
from apps.accounts.tokens import read_access
from apps.common.errors import WWW_AUTHENTICATE, ApiError, ErrorCode

if TYPE_CHECKING:
    from rest_framework.request import Request
    from rest_framework_simplejwt.tokens import Token


class PlayerAuthentication(JWTAuthentication):
    def authenticate_header(self, request: Request) -> str:
        return WWW_AUTHENTICATE

    def get_validated_token(self, raw_token: bytes) -> Token:
        try:
            return read_access(raw_token)
        except ExpiredTokenError:
            raise ApiError(ErrorCode.TOKEN_EXPIRED) from None
        except TokenError:
            raise ApiError(ErrorCode.TOKEN_INVALID) from None

    def get_user(self, validated_token: Token) -> Player:  # type: ignore[override]
        """One indexed query. A missing row is `token_invalid`, a deleted player
        `account_deleted` (FR-014)."""
        try:
            player = Player.objects.get(pk=uuid.UUID(str(validated_token["sub"])))
        except (KeyError, ValueError, Player.DoesNotExist):
            raise ApiError(ErrorCode.TOKEN_INVALID) from None
        if not player.is_active:
            raise ApiError(ErrorCode.ACCOUNT_DELETED)
        return player
