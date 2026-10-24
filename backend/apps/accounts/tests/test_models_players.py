"""The player tables and their constraints (B02 data-model.md)."""

from __future__ import annotations

import pytest
from django.core.management import call_command
from django.db import IntegrityError, transaction
from django.db.models import ProtectedError
from django.utils import timezone

from apps.accounts.models import Device, Identity, Player, PlayerSession
from apps.accounts.tests.factories import make_device, make_player
from apps.common.ids import uuid7

pytestmark = pytest.mark.django_db


def make_session(player: Player, device: Device) -> PlayerSession:
    now = timezone.now()
    return PlayerSession.objects.create(
        player=player,
        device=device,
        current_jti=uuid7(),
        current_issued_at=now,
        current_expires_at=now,
        current_kid="test1",
        last_renewed_at=now,
    )


def test_one_device_per_install_id_hash() -> None:
    device = make_device(make_player())
    with pytest.raises(IntegrityError), transaction.atomic():
        make_device(make_player(), install_id_hash=device.install_id_hash)


def test_one_player_row_per_provider_account() -> None:
    first, second = make_player(), make_player()
    Identity.objects.create(
        player=first, provider="google", subject="g-1", linked_at=timezone.now()
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        Identity.objects.create(
            player=second, provider="google", subject="g-1", linked_at=timezone.now()
        )


def test_one_account_per_provider_per_player() -> None:
    player = make_player()
    Identity.objects.create(
        player=player, provider="google", subject="g-1", linked_at=timezone.now()
    )
    with pytest.raises(IntegrityError), transaction.atomic():
        Identity.objects.create(
            player=player, provider="google", subject="g-2", linked_at=timezone.now()
        )


def test_driver_level_is_at_least_one() -> None:
    with pytest.raises(IntegrityError), transaction.atomic():
        make_player(driver_level=0)


def test_defaults() -> None:
    player = make_player()
    player.refresh_from_db()
    assert player.status == "active"
    assert player.driver_level == 1
    assert player.is_tester is False
    assert player.display_name == ""
    session = make_session(player, make_device(player))
    session.refresh_from_db()
    assert session.status == "active"
    assert session.end_reason == ""
    assert session.ended_at is None
    assert session.previous_jti is None


def test_is_authenticated_is_a_property_not_a_column() -> None:
    player = make_player()
    assert player.is_authenticated is True
    assert "is_authenticated" not in {field.name for field in Player._meta.get_fields()}


def test_every_player_table_has_a_uuid7_key() -> None:
    call_command("check", "--fail-level", "ERROR")  # common.E001 covers the four models
    player = make_player()
    device = make_device(player)
    identity = Identity.objects.create(
        player=player, provider="google", subject="g-1", linked_at=timezone.now()
    )
    for row in (player, device, identity, make_session(player, device)):
        assert row.id.version == 7


def test_deleting_a_player_with_devices_is_refused() -> None:
    """Devices and identities are PROTECT: B09 removes them on purpose, never by cascade."""
    player = make_player()
    make_device(player)
    with pytest.raises(ProtectedError):
        Player.objects.filter(pk=player.pk).delete()
