"""The economy on a player's admin page (contracts/admin.md "On the player page", "Adjusting a
balance"). `accounts.admin.PlayerAdmin` renders these blocks and routes the adjustment here.

Each block is shown only to a staff user who may view its model. Nothing here reads a payload, a
token, an install id or a provider subject.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from django import forms
from django.contrib.admin import ModelAdmin
from django.core.exceptions import PermissionDenied
from django.http import Http404, HttpRequest, HttpResponse, HttpResponseRedirect
from django.template.response import TemplateResponse
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import Player, User
from apps.common.ids import uuid7
from apps.economy.models import (
    Currency,
    GrantRecord,
    Inventory,
    LedgerEntry,
    PlayerFlag,
    ProcessedOp,
    Wallet,
    WalletAdjustment,
)
from apps.economy.services import adjustments, settings, wallets
from apps.progress.models import Ownership, StoryState, TripProgress

RECENT = 50
ADJUST_PERMISSION = "economy.adjust_wallet"
MAX_ADJUSTMENT = 10**9


@dataclass(frozen=True)
class Block:
    title: str
    headers: tuple[str, ...]
    rows: list[tuple[Any, ...]]
    links: list[tuple[str, str]] = field(default_factory=list)  # (text, url)


def blocks(user: Any, player: Player) -> list[Block]:
    """The blocks `user` may see, in the order of contracts/admin.md."""
    shown: list[Block] = []
    for permission, build in (
        ("economy.view_wallet", _wallet),
        ("economy.view_ledgerentry", _ledger),
        ("economy.view_inventory", _inventory),
        ("progress.view_ownership", _ownership),
        ("progress.view_tripprogress", _progress),
        ("progress.view_storystate", _story),
        ("economy.view_grantrecord", _grants),
        ("economy.view_playerflag", _flags),
        ("economy.view_processedop", _operations),
    ):
        if user.has_perm(permission):
            shown.append(build(player))
    shown.append(_adjustments(player))  # visible to anyone who can view the player
    return shown


def _wallet(player: Player) -> Block:
    wallet = Wallet.objects.filter(pk=player.pk).first()
    if wallet is None:
        return Block("Wallet", ("", ""), [])
    now = timezone.now()
    shown = wallets.answer(wallet, player, now, settings.current())
    rows = [
        ("JENEHAT", wallet.jenehat),
        ("BONAT", wallet.bonat),
        ("Fuel now", f"{shown['fuel']} of {shown['fuel_max']}"),
        ("Unlimited fuel until", shown["fuel_unlimited_until"] or "-"),
        ("State version", wallet.state_version),
        ("Last active", wallet.last_active_at),
        ("Comeback return", wallet.comeback_return_at or "-"),
    ]
    return Block("Wallet", ("", ""), rows)


def _ledger(player: Player) -> Block:
    entries = LedgerEntry.objects.filter(player=player).order_by("-created_at", "-id")[:RECENT]
    rows = [
        (
            e.created_at,
            e.currency,
            f"{e.delta:+d}",
            e.balance_after,
            e.reason,
            e.source,
            f"{e.ref_type} {e.ref_id}".strip(),
        )
        for e in entries
    ]
    url = f"{reverse('admin:economy_ledgerentry_changelist')}?q={player.pk}"
    return Block(
        "Recent ledger",
        ("Time", "Currency", "Delta", "Balance after", "Reason", "Source", "Reference"),
        rows,
        [("The full ledger", url)],
    )


def _inventory(player: Player) -> Block:
    rows = list(
        Inventory.objects.filter(player=player)
        .order_by("booster_id")
        .values_list("booster_id", "count")
    )
    return Block("Inventory", ("Booster", "Count"), rows)


def _ownership(player: Player) -> Block:
    rows = list(
        Ownership.objects.filter(player=player)
        .order_by("kind", "sku_id")
        .values_list("kind", "sku_id", "variant", "acquired_at")
    )
    return Block("Ownership", ("Kind", "Id", "Variant", "Acquired"), rows)


def _progress(player: Player) -> Block:
    rows = list(
        TripProgress.objects.filter(player=player)
        .order_by("trip_id")
        .values_list("trip_id", "best_stars", "best_time_ms", "plays")
    )
    return Block("Trip progress", ("Trip", "Best stars", "Best time (ms)", "Plays"), rows)


def _story(player: Player) -> Block:
    rows = [
        (chapter, status, ", ".join(scenes))
        for chapter, status, scenes in StoryState.objects.filter(player=player)
        .order_by("chapter_id")
        .values_list("chapter_id", "status", "scenes_seen")
    ]
    return Block("Story", ("Chapter", "Status", "Scenes seen"), rows)


def _grants(player: Player) -> Block:
    rows = list(
        GrantRecord.objects.filter(player=player)
        .order_by("granted_at", "kind")
        .values_list("kind", "key", "granted_at")
    )
    return Block("Grants", ("Kind", "Key", "Granted"), rows)


def _flags(player: Player) -> Block:
    rows = list(
        PlayerFlag.objects.filter(player=player, reviewed_at__isnull=True)
        .order_by("-game_date", "kind")
        .values_list("kind", "game_date", "details")
    )
    url = f"{reverse('admin:economy_playerflag_changelist')}?q={player.pk}"
    return Block("Open flags", ("Kind", "Date", "Details"), rows, [("Review", url)])


def _operations(player: Player) -> Block:
    rows = list(
        ProcessedOp.objects.filter(player=player)
        .order_by("-processed_at", "-id")
        .values_list("processed_at", "op_type", "status", "reason")[:RECENT]
    )
    return Block("Recent operations", ("Time", "Type", "Status", "Reason"), rows)


def _adjustments(player: Player) -> Block:
    rows = [
        (a.at, a.currency, f"{a.delta:+d}", a.reason, a.actor.username)
        for a in WalletAdjustment.objects.filter(player=player)
        .select_related("actor")
        .order_by("-at")[:RECENT]
    ]
    return Block("Adjustments", ("Time", "Currency", "Delta", "Reason", "By"), rows)


# -- adjusting a balance ---------------------------------------------------------------------------


class AdjustForm(forms.Form):
    currency = forms.ChoiceField(choices=[(c, c) for c in (Currency.JENEHAT, Currency.BONAT)])
    amount = forms.IntegerField(
        min_value=-MAX_ADJUSTMENT,
        max_value=MAX_ADJUSTMENT,
        help_text="Signed: negative takes away.",
    )
    reason = forms.CharField(max_length=adjustments.MAX_REASON_LENGTH)
    confirm = forms.BooleanField(
        required=False, label="I have checked the player, the currency and the amount."
    )
    # One per form shown: the adjustment's id, so submitting the form twice applies it once.
    token = forms.UUIDField(widget=forms.HiddenInput)

    def clean_amount(self) -> int:
        amount: int = self.cleaned_data["amount"]
        if amount == 0:
            raise forms.ValidationError("The amount can't be 0.")
        return amount


def adjust_view(
    model_admin: ModelAdmin[Player], request: HttpRequest, object_id: str
) -> HttpResponse:
    if not request.user.has_perm(ADJUST_PERMISSION):
        raise PermissionDenied
    player = model_admin.get_object(request, object_id)
    if player is None:
        raise Http404("No such player.")
    if not model_admin.has_view_or_change_permission(request, player):
        raise PermissionDenied
    wallet = Wallet.objects.filter(pk=player.pk).first()
    balances = {
        Currency.JENEHAT: wallet.jenehat if wallet else 0,
        Currency.BONAT: wallet.bonat if wallet else 0,
    }
    if request.method == "POST":
        form = AdjustForm(request.POST)
    else:
        form = AdjustForm(initial={"token": uuid7()})
    preview = None
    if form.is_bound and form.is_valid():
        currency, amount = form.cleaned_data["currency"], form.cleaned_data["amount"]
        token = form.cleaned_data["token"]
        if WalletAdjustment.objects.filter(pk=token, player=player).exists():
            model_admin.message_user(request, "This adjustment was already applied.")
            return HttpResponseRedirect(reverse("admin:accounts_player_change", args=[player.pk]))
        before = balances[currency]
        preview = f"{currency}: {before} → {before + amount}"
        if before + amount < 0:
            form.add_error("amount", f"The balance would go below 0 ({preview}).")
        elif not form.cleaned_data["confirm"]:
            form.add_error("confirm", "Tick the box to apply this adjustment.")
        else:
            actor: User = request.user  # type: ignore[assignment]  # the admin's staff user
            try:
                adjustments.adjust(
                    player,
                    currency,
                    amount,
                    form.cleaned_data["reason"],
                    actor,
                    record_id=token,
                )
            except adjustments.AdjustmentRefused as refused:
                form.add_error(None, str(refused))
            else:
                model_admin.message_user(request, f"{currency} adjusted by {amount:+d}.")
                return HttpResponseRedirect(
                    reverse("admin:accounts_player_change", args=[player.pk])
                )
    context = {
        **model_admin.admin_site.each_context(request),
        "title": "Adjust balance",
        "opts": Player._meta,
        "original": player,
        "form": form,
        "balances": balances,
        "preview": preview,
    }
    return TemplateResponse(request, "admin/economy/adjust.html", context)
