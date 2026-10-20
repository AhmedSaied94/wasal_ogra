"""Who may do what (research R9, FR-019).

Every service checks the permission itself, so a job or command started without it is refused
too. The environment's `CONTENT_ROLE` decides what is offered at all.
"""

from __future__ import annotations

from django.conf import settings
from django.core.exceptions import PermissionDenied

from apps.accounts.models import User

SOURCE = "source"
TARGET = "target"


def require(actor: User | None, perm: str) -> User:
    """`actor`, if it is an active staff member with `perm` (`content.build_pack`)."""
    if actor is None or not actor.is_active or not actor.is_staff:
        raise PermissionDenied(f"{perm} needs an active staff account")
    if not actor.has_perm(perm):
        raise PermissionDenied(f"{perm} is required")
    return actor


def require_staff(actor: User | None) -> User:
    """`actor`, if it is an active staff member: enough to read and export published packs."""
    if actor is None or not actor.is_active or not actor.is_staff:
        raise PermissionDenied("this needs an active staff account")
    return actor


def role() -> str:
    return str(settings.CONTENT_ROLE)


def require_role(*roles: str) -> None:
    current = role()
    if current not in roles:
        raise PermissionDenied(
            f"not offered with CONTENT_ROLE={current} (needs {' or '.join(roles)})"
        )
