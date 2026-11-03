"""The ad rewards, read-only (B07 contracts/admin.md, research R14).

No one adds, changes or deletes a reward here, superusers included: a missing reward is corrected
by a staff adjustment with its reason (docs/runbooks/economy.md).
"""

from __future__ import annotations

from typing import Any

from django.contrib import admin
from django.http import HttpRequest
from django.urls import reverse
from django.utils.html import format_html, format_html_join
from django.utils.safestring import SafeString

from apps.ads.models import AdReward
from apps.economy.models import LedgerEntry


@admin.register(AdReward)
class AdRewardAdmin(admin.ModelAdmin):  # type: ignore[type-arg]
    actions = None
    list_display = (
        "created_at",
        "player_link",
        "placement",
        "outcome",
        "jenehat",
        "bonat",
        "game_date",
        "shown_at",
    )
    list_filter = ("placement", "outcome")
    date_hierarchy = "game_date"
    list_select_related = ("player",)
    search_fields = ("=player__id", "=transaction_id")
    search_help_text = "An exact player_id (the full UUID) or an exact AdMob transaction id."
    ordering = ("-created_at", "-id")
    readonly_fields = ("ledger_entries",)

    def has_add_permission(self, request: HttpRequest) -> bool:
        return False

    def has_change_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    def has_delete_permission(self, request: HttpRequest, obj: Any = None) -> bool:
        return False

    @admin.display(description="Player", ordering="player")
    def player_link(self, reward: AdReward) -> SafeString | str:
        if reward.player_id is None:
            return "-"
        url = reverse("admin:accounts_player_change", args=[reward.player_id])
        return format_html('<a href="{}">{}</a>', url, reward.player_id)

    @admin.display(description="Ledger entries")
    def ledger_entries(self, reward: AdReward) -> SafeString | str:
        entries = LedgerEntry.objects.filter(ref_type="ad_reward", ref_id=str(reward.pk)).order_by(
            "currency"
        )
        if not entries:
            return "-"
        return format_html_join(
            "",
            '<div><a href="{}">{} {}</a></div>',
            (
                (
                    reverse("admin:economy_ledgerentry_change", args=[e.pk]),
                    e.currency,
                    f"{e.delta:+d}",
                )
                for e in entries
            ),
        )
