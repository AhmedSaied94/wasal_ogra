"""The economy in the staff admin (B03 tasks.md T079, contracts/admin.md, SC-011)."""

from __future__ import annotations

import uuid
from datetime import date

import pytest
from django.contrib.auth.models import Group
from django.test import Client
from django.utils import timezone

from apps.accounts.models import Identity, NameFilterEntry, Player, User
from apps.accounts.tests.factories import make_device, make_player
from apps.content.tests.conftest import admin_client
from apps.economy.models import Currency, LedgerEntry, PlayerFlag, ProcessedOp, WalletAdjustment
from apps.economy.services import adjustments
from apps.economy.tests.helpers import grant, wallet_of

pytestmark = [pytest.mark.django_db, pytest.mark.urls("config.urls_admin")]

PLAYERS = "/admin/accounts/player/"
FLAGS = "/admin/economy/playerflag/"
ADJUSTMENTS = "/admin/economy/walletadjustment/"
LEDGER = "/admin/economy/ledgerentry/"
NAMES = "/admin/accounts/namefilterentry/"
INSTALL_ID = uuid.UUID("6f1c2b9a-3d4e-4f5a-8b6c-7d8e9f0a1b2c")
SUBJECT = "109876543210987654321"
PAYLOAD_SECRET = "a-payload-value-never-shown"


def staff(username: str, group: str | None = None) -> Client:
    user = User.objects.create_user(username, is_staff=True)
    if group:
        user.groups.add(Group.objects.get(name=group))
    return admin_client(user)


@pytest.fixture
def support() -> Client:
    return staff("support1", "player_support")


@pytest.fixture
def ops() -> Client:
    return staff("ops1", "economy_ops")


@pytest.fixture
def nobody() -> Client:
    return staff("plain1")


@pytest.fixture
def player() -> Player:
    """A player with money, an operation, a flag and the secrets no page may show."""
    player = make_player()
    make_device(player, INSTALL_ID)
    Identity.objects.create(
        player=player, provider="google", subject=SUBJECT, linked_at=timezone.now()
    )
    grant(player, Currency.JENEHAT, 500)
    grant(player, Currency.BONAT, 40)
    ProcessedOp.objects.create(
        player=player,
        client_txn_id=uuid.uuid4(),
        op_type="spend_bonat",
        payload_hash="0" * 64,
        status="rejected",
        reason="price_mismatch",
        result={"note": PAYLOAD_SECRET},
        processed_at=timezone.now(),
    )
    PlayerFlag.objects.create(
        player=player, kind="fast_three_star", game_date=date(2026, 10, 24), details={"count": 1}
    )
    return player


def page(player: Player) -> str:
    return f"{PLAYERS}{player.pk}/change/"


def adjust_page(player: Player) -> str:
    return f"{PLAYERS}{player.pk}/adjust/"


# -- the player page -------------------------------------------------------------------------------


def test_support_sees_the_economy_blocks_without_secrets(support: Client, player: Player) -> None:
    response = support.get(page(player))
    assert response.status_code == 200
    html = response.content.decode()
    for block in (
        "Wallet",
        "Recent ledger",
        "Inventory",
        "Ownership",
        "Trip progress",
        "Story",
        "Grants",
        "Open flags",
        "Recent operations",
        "Adjustments",
    ):
        assert f"<h2>{block}</h2>" in html, block
    assert "price_mismatch" in html
    assert "spend_bonat" in html
    assert "fast_three_star" in html
    for secret in (PAYLOAD_SECRET, str(INSTALL_ID), SUBJECT, "0" * 64):
        assert secret not in html
    assert "Adjust balance" not in html  # support has no adjust permission


def test_a_staff_user_without_the_groups_is_refused(nobody: Client, player: Player) -> None:
    assert nobody.get(page(player)).status_code == 403
    assert nobody.get(FLAGS).status_code == 403
    assert nobody.get(adjust_page(player)).status_code == 403


def test_ops_sees_the_adjust_link(ops: Client, player: Player) -> None:
    html = ops.get(page(player)).content.decode()
    assert "Adjust balance" in html
    assert adjust_page(player) in html


# -- adjusting a balance ---------------------------------------------------------------------------


def post_adjustment(client: Client, player: Player, **fields: str) -> int:
    data = {
        "currency": "BONAT",
        "amount": "10",
        "reason": "refund for a lost purchase",
        "token": str(uuid.uuid4()),
    }
    status: int = client.post(adjust_page(player), {**data, **fields}).status_code
    return status


def test_the_adjustment_shows_before_and_after_and_needs_confirming(
    ops: Client, player: Player
) -> None:
    form = ops.get(adjust_page(player)).content.decode()
    assert "JENEHAT 500, BONAT 40" in form  # the balances before
    preview = ops.post(
        adjust_page(player),
        {"currency": "BONAT", "amount": "-15", "reason": "a mistake", "token": str(uuid.uuid4())},
    ).content.decode()
    assert "40 → 25" in preview
    assert wallet_of(player).bonat == 40


def test_an_adjustment_writes_one_entry_and_one_record(ops: Client, player: Player) -> None:
    version = wallet_of(player).state_version
    assert post_adjustment(ops, player, confirm="on") == 302
    wallet = wallet_of(player)
    assert (wallet.bonat, wallet.state_version) == (50, version + 1)
    record = WalletAdjustment.objects.get(player=player)
    entry = record.ledger_entry
    assert (entry.reason, entry.source, entry.delta, entry.currency) == (
        "admin_adjustment",
        "admin",
        10,
        "BONAT",
    )
    assert (entry.ref_type, entry.ref_id) == ("adjustment", str(record.pk))
    assert record.actor.username == "ops1"
    assert (record.currency, record.delta, record.reason) == (
        "BONAT",
        10,
        "refund for a lost purchase",
    )
    assert "refund for a lost purchase" in ops.get(page(player)).content.decode()


def test_a_form_sent_twice_adjusts_once(ops: Client, player: Player) -> None:
    token = str(uuid.uuid4())
    assert post_adjustment(ops, player, confirm="on", token=token) == 302
    assert post_adjustment(ops, player, confirm="on", token=token) == 302
    assert WalletAdjustment.objects.count() == 1
    assert wallet_of(player).bonat == 50


def test_the_form_carries_a_fresh_token(ops: Client, player: Player) -> None:
    first, second = (ops.get(adjust_page(player)).content.decode() for _ in range(2))
    assert 'name="token"' in first
    assert (
        first.split('name="token" value="')[1][:36] != second.split('name="token" value="')[1][:36]
    )


def test_a_result_below_zero_is_refused(ops: Client, player: Player) -> None:
    assert post_adjustment(ops, player, amount="-41", confirm="on") == 200
    assert wallet_of(player).bonat == 40
    assert not WalletAdjustment.objects.exists()


@pytest.mark.parametrize(
    "fields",
    [
        {"amount": "0"},
        {"amount": "1.5"},
        {"reason": ""},
        {"reason": "x" * 201},
        {"currency": "FUEL"},
        {"token": "not-a-token"},
    ],
)
def test_a_bad_form_is_refused(ops: Client, player: Player, fields: dict[str, str]) -> None:
    assert post_adjustment(ops, player, confirm="on", **fields) == 200
    assert not WalletAdjustment.objects.exists()


def test_support_cannot_adjust(support: Client, player: Player) -> None:
    assert post_adjustment(support, player, confirm="on") == 403
    assert wallet_of(player).bonat == 40


def test_the_service_refuses_below_zero_and_a_zero_delta(player: Player) -> None:
    actor = User.objects.create_user("ops2", is_staff=True)
    entries = LedgerEntry.objects.filter(player=player).count()
    with pytest.raises(adjustments.AdjustmentRefused):
        adjustments.adjust(player, Currency.JENEHAT, -501, "too much", actor)
    with pytest.raises(adjustments.AdjustmentRefused):
        adjustments.adjust(player, Currency.JENEHAT, 0, "nothing", actor)
    assert LedgerEntry.objects.filter(player=player).count() == entries
    assert not WalletAdjustment.objects.exists()


def test_adjustments_cannot_be_changed_or_deleted(ops: Client, player: Player) -> None:
    post_adjustment(ops, player, confirm="on")
    record = WalletAdjustment.objects.get()
    assert ops.get(ADJUSTMENTS).status_code == 200
    detail = f"{ADJUSTMENTS}{record.pk}/change/"
    assert ops.post(detail, {"reason": "edited"}).status_code == 403
    assert ops.get(f"{ADJUSTMENTS}{record.pk}/delete/").status_code == 403
    assert WalletAdjustment.objects.get().reason == "refund for a lost purchase"


# -- flags -----------------------------------------------------------------------------------------


def review(client: Client, flag: PlayerFlag, resolution: str) -> str:
    data = {
        "action": "mark_reviewed",
        "_selected_action": [str(flag.pk)],
        "apply": "1",
        "resolution": resolution,
    }
    return client.post(FLAGS, data, follow=True).content.decode()


def test_the_flag_list_shows_open_flags_by_default(support: Client, player: Player) -> None:
    reviewed = PlayerFlag.objects.create(
        player=player,
        kind="trip_rate",
        game_date=date(2026, 10, 23),
        reviewed_at=timezone.now(),
        resolution="fine",
    )
    rows = support.get(FLAGS).content.decode().split("<tbody>")[1].split("</tbody>")[0]
    assert "fast_three_star" in rows
    assert str(reviewed.pk) not in rows
    assert "trip_rate" not in rows


def test_a_review_records_who_when_and_why_once(support: Client, player: Player) -> None:
    flag = PlayerFlag.objects.get(player=player)
    review(support, flag, "a fast but honest player")
    flag.refresh_from_db()
    assert flag.reviewed_by is not None
    assert flag.reviewed_by.username == "support1"
    assert flag.reviewed_at is not None
    assert flag.resolution == "a fast but honest player"
    review(support, flag, "changed my mind")
    flag.refresh_from_db()
    assert flag.resolution == "a fast but honest player"


@pytest.mark.parametrize("resolution", ["", "x" * 201])
def test_a_review_needs_a_short_resolution(
    support: Client, player: Player, resolution: str
) -> None:
    flag = PlayerFlag.objects.get(player=player)
    review(support, flag, resolution)
    flag.refresh_from_db()
    assert flag.reviewed_at is None


def test_flags_cannot_be_added_edited_or_deleted(support: Client, player: Player) -> None:
    flag = PlayerFlag.objects.get(player=player)
    assert support.get(f"{FLAGS}add/").status_code == 403
    assert support.get(f"{FLAGS}{flag.pk}/delete/").status_code == 403
    response = support.post(f"{FLAGS}{flag.pk}/change/", {"resolution": "edited"})
    assert response.status_code == 403
    flag.refresh_from_db()
    assert (flag.resolution, flag.reviewed_at) == ("", None)


def test_the_ledger_list_is_read_only(support: Client, player: Player) -> None:
    entry = LedgerEntry.objects.filter(player=player).first()
    assert entry is not None
    assert support.get(LEDGER, {"q": str(player.pk)}).status_code == 200
    assert support.get(f"{LEDGER}{entry.pk}/delete/").status_code == 403
    assert support.post(f"{LEDGER}{entry.pk}/change/", {"delta": "1"}).status_code == 403


# -- the name filter -------------------------------------------------------------------------------


def test_ops_edits_the_name_filter_and_sees_the_normalized_form(ops: Client) -> None:
    response = ops.post(f"{NAMES}add/", {"term": "حمــار"}, follow=True)
    assert response.status_code == 200
    entry = NameFilterEntry.objects.get(term="حمــار")
    assert entry.normalized == "حمار"
    assert entry.added_by is not None
    assert entry.added_by.username == "ops1"
    assert "حمار" in ops.get(NAMES).content.decode()


def test_support_cannot_edit_the_name_filter(support: Client) -> None:
    assert support.get(NAMES).status_code == 403
    assert support.post(f"{NAMES}add/", {"term": "x"}).status_code == 403
