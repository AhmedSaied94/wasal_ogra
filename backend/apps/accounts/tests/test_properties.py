"""SC-006, FR-042: random sequences of creation, renewal, linking and resolving keep the rules.

A hypothesis state machine drives the three endpoints over 4 install ids and 3 Google accounts,
with a clock it moves. After every step: one device per install id, one holder per Google account,
no player over the session cap, and no player data but FR-018's fields changed. Every request is
sent twice, and the repeat must answer the same (tokens aside, as contracts/tokens.md says).

300 examples in the normal run; `HYPOTHESIS_PROFILE=thorough` runs 10,000 (quickstart A1).
"""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime
from typing import Any, ClassVar

import pytest
import time_machine
from django.conf import settings
from django.db import transaction
from django.db.models import Count
from django.forms.models import model_to_dict
from django.test import Client
from django.utils import timezone
from hypothesis import settings as hypothesis_settings
from hypothesis import strategies as st
from hypothesis.stateful import (
    RuleBasedStateMachine,
    invariant,
    precondition,
    rule,
    run_state_machine_as_test,
)

from apps.accounts import tokens
from apps.accounts.models import Device, Identity, Player, PlayerSession
from apps.accounts.tests.conftest import MakeToken
from apps.accounts.tests.factories import HEADERS, LINK, renew, sign_in

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("no_throttle", "google_jwks")]

T0 = datetime(2026, 10, 24, 12, 0, tzinfo=UTC)
INSTALLS = [uuid.UUID(f"3b0b9d3e-6f1a-4c8e-9f7a-2d5c1e8b4a9{n}") for n in range(4)]
SUBJECTS = ["G0", "G1", "G2"]
STEPS = [5, 59, 61, 900, 30 * 86400]
ISSUE_FIELDS = {"last_seen_at", "client_version", "platform", "updated_at"}
TOKEN_FIELDS = {"access", "refresh"}


def without_tokens(response: Any) -> dict[str, Any]:
    body: dict[str, Any] = json.loads(response.content)
    return {key: value for key, value in body.items() if key not in TOKEN_FIELDS}


def players_now() -> dict[str, dict[str, Any]]:
    return {
        str(row.pk): {k: v for k, v in model_to_dict(row).items() if k not in ISSUE_FIELDS}
        for row in Player.objects.all()
    }


class AuthMachine(RuleBasedStateMachine):
    make_token: ClassVar[MakeToken]

    def __init__(self) -> None:
        super().__init__()
        self.atomic = transaction.atomic()
        self.atomic.__enter__()
        self.travel = time_machine.travel(T0, tick=False)
        self.clock = self.travel.start()
        self.client = Client()
        self.chains: list[list[str]] = []  # each session's refresh tokens, oldest first
        self.sessions: list[tuple[str, str]] = []  # (player_id, session_id), one per chain
        self.conflicts: dict[tuple[str, str], str] = {}  # (player, subject) -> holder in the 409

    def teardown(self) -> None:
        self.travel.stop()
        transaction.set_rollback(True)
        self.atomic.__exit__(None, None, None)

    # -- helpers -------------------------------------------------------------------------------

    def track(self, body: dict[str, Any]) -> None:
        claims = tokens.decode_refresh(body["refresh"], verify_exp=False)
        self.chains.append([body["refresh"]])
        self.sessions.append((str(claims.player_id), str(claims.session_id)))

    def link(self, player_id: str, session_id: str, subject: str, **extra: str) -> Any:
        access = tokens.mint_access(uuid.UUID(player_id), uuid.UUID(session_id))
        return self.client.post(
            LINK,
            data={"provider": "google", "id_token": self.make_token(subject), **extra},
            content_type="application/json",
            headers={**HEADERS, "authorization": f"Bearer {access}"},
        )

    def twice(self, send: Any) -> tuple[Any, Any]:
        """Send a request and its repeat; nothing but FR-018's fields may change on players."""
        before = players_now()
        first, second = send(), send()
        after = players_now()
        assert {pk: after[pk] for pk in before} == before
        return first, second

    # -- rules ---------------------------------------------------------------------------------

    @rule(install=st.sampled_from(INSTALLS))
    def anonymous(self, install: uuid.UUID) -> None:
        first, second = self.twice(lambda: sign_in(self.client, install))
        assert first.status_code in (200, 201)
        assert second.status_code == 200
        assert second.json()["player_id"] == first.json()["player_id"]
        self.track(first.json())
        self.track(second.json())

    @precondition(lambda self: self.chains)
    @rule(data=st.data(), which=st.sampled_from(["current", "previous", "older"]))
    def refresh(self, data: st.DataObject, which: str) -> None:
        chain = data.draw(st.sampled_from(self.chains))
        token = {"current": chain[-1], "previous": chain[max(0, len(chain) - 2)], "older": chain[0]}
        first, second = self.twice(lambda: renew(self.client, token[which]))
        assert first.status_code in (200, 401, 403)
        assert second.status_code == first.status_code
        if first.status_code == 200:
            assert first.json()["refresh"] == second.json()["refresh"]  # the replay
            if first.json()["refresh"] != chain[-1]:
                chain.append(first.json()["refresh"])
        else:
            assert second.json()["error"]["code"] == first.json()["error"]["code"]

    @rule(seconds=st.sampled_from(STEPS))
    def advance(self, seconds: int) -> None:
        self.clock.shift(seconds)

    @precondition(lambda self: self.sessions)
    @rule(data=st.data(), subject=st.sampled_from(SUBJECTS))
    def link_google(self, data: st.DataObject, subject: str) -> None:
        player_id, session_id = data.draw(st.sampled_from(self.sessions))
        first, second = self.twice(lambda: self.link(player_id, session_id, subject))
        assert first.status_code in (200, 403, 409)
        assert second.status_code == first.status_code
        assert without_tokens(second) == without_tokens(first)
        error = first.json().get("error", {})
        if error.get("code") == "provider_in_use":
            self.conflicts[(player_id, subject)] = error["details"]["existing"]["player_id"]

    @precondition(lambda self: self.conflicts)
    @rule(data=st.data(), choice=st.sampled_from(["switch_to_existing", "keep_current"]))
    def resolve(self, data: st.DataObject, choice: str) -> None:
        (player_id, subject), holder = data.draw(st.sampled_from(sorted(self.conflicts.items())))
        del self.conflicts[(player_id, subject)]
        session_id = next(sid for pid, sid in reversed(self.sessions) if pid == player_id)
        # The device this session signed in on may have gone to another player since (a sign-in
        # by its install id after this player stopped being active). A switch can't take it.
        device = PlayerSession.objects.get(pk=session_id).device
        taken = str(device.player_id) not in (player_id, holder)
        first, second = self.twice(
            lambda: self.link(
                player_id, session_id, subject, resolve=choice, existing_player_id=holder
            )
        )
        if first.status_code == 401:
            assert choice == "switch_to_existing"
            assert taken
            assert first.json()["error"]["code"] == "token_invalid"
        else:
            assert first.status_code in (200, 403, 409)
        assert second.status_code == first.status_code
        assert without_tokens(second) == without_tokens(first)
        if first.status_code == 200 and "refresh" in first.json():
            assert first.json()["player_id"] == holder
            self.track(first.json())
            self.track(second.json())

    @precondition(lambda self: self.sessions)
    @rule(data=st.data(), status=st.sampled_from(["active", "pending_deletion", "deleted"]))
    def set_status(self, data: st.DataObject, status: str) -> None:
        player_id, _ = data.draw(st.sampled_from(self.sessions))
        Player.objects.filter(pk=player_id).update(status=status)

    # -- invariants ----------------------------------------------------------------------------

    @invariant()
    def one_device_per_install_id(self) -> None:
        repeated = Device.objects.values("install_id_hash").annotate(n=Count("id")).filter(n__gt=1)
        assert not repeated.exists()

    @invariant()
    def one_holder_per_google_account(self) -> None:
        repeated = (
            Identity.objects.values("provider", "subject").annotate(n=Count("id")).filter(n__gt=1)
        )
        assert not repeated.exists()
        assert (
            Identity.objects.values("player").annotate(n=Count("id")).filter(n__gt=1).count() == 0
        )

    @invariant()
    def no_player_over_the_cap(self) -> None:
        live = (
            PlayerSession.objects.filter(status="active", current_expires_at__gt=timezone.now())
            .values("player")
            .annotate(n=Count("id"))
            .filter(n__gt=settings.AUTH_MAX_SESSIONS_PER_PLAYER)
        )
        assert not live.exists()


def test_random_sequences_keep_the_rules(make_google_token: MakeToken, settings: Any) -> None:
    settings.GOOGLE_KEYS_CACHE_SECONDS = 3600
    AuthMachine.make_token = staticmethod(make_google_token)
    run_state_machine_as_test(  # type: ignore[no-untyped-call]  # hypothesis leaves it untyped
        AuthMachine, settings=hypothesis_settings(stateful_step_count=15)
    )
