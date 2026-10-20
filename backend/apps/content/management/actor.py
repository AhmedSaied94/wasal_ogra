"""The `--actor` every content command that acts for a person needs (contracts/admin.md)."""

from __future__ import annotations

from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from apps.accounts.models import User


def add_actor_argument(parser: CommandParser) -> None:
    parser.add_argument(
        "--actor",
        required=True,
        help="The staff username the command acts for. Its permissions are checked.",
    )


def resolve_actor(username: str) -> User:
    """The actor's account. An unknown username stops the command before it does anything."""
    try:
        return User.objects.get_by_natural_key(username)
    except User.DoesNotExist:
        raise CommandError(f"There is no user {username.lower()!r}.") from None


class PackVersionCommand(BaseCommand):
    """A command whose `--version N` names a pack (contracts/admin.md), replacing Django's own
    `--version`, which would print Django's version."""

    def create_parser(self, prog_name: str, subcommand: str, **kwargs: Any) -> CommandParser:
        return super().create_parser(prog_name, subcommand, conflict_handler="resolve", **kwargs)
