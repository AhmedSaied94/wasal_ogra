"""Two crossed links can't deadlock: players are locked in id order (B02 research R7)."""

from __future__ import annotations

import threading

import pytest
from django.db import connection

from apps.accounts.models import Identity
from apps.accounts.tests.conftest import MakeToken, SignedIn, signed_in

pytestmark = [
    pytest.mark.django_db(transaction=True),
    pytest.mark.usefixtures("no_throttle", "google_jwks"),
]


def test_two_players_each_reaching_for_the_other_s_account_never_deadlock(
    make_google_token: MakeToken,
) -> None:
    """Each request locks both players' rows before it decides. Locked in id order, the two
    requests queue on the same row instead of each holding what the other waits for. Neither can
    take the other's account, since each already has one (FR-024), so both answer 409 rather than
    a deadlock's 503, and each account keeps its one holder."""
    first, second = signed_in(), signed_in()
    assert first.link(make_google_token("G-first")).status_code == 200
    assert second.link(make_google_token("G-second")).status_code == 200
    barrier = threading.Barrier(2)
    codes: list[str] = []

    def take(taker: SignedIn, subject: str, holder_id: str) -> None:
        try:
            barrier.wait()
            response = taker.link(
                make_google_token(subject), resolve="keep_current", existing_player_id=holder_id
            )
            codes.append(response.json()["error"]["code"])
        finally:
            connection.close()

    threads = [
        threading.Thread(target=take, args=(first, "G-second", second.player_id)),
        threading.Thread(target=take, args=(second, "G-first", first.player_id)),
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert codes == ["provider_already_linked", "provider_already_linked"]
    holders = dict(Identity.objects.values_list("subject", "player_id"))
    assert {subject: str(player) for subject, player in holders.items()} == {
        "G-first": first.player_id,
        "G-second": second.player_id,
    }


def test_two_players_taking_one_account_at_once_leave_one_holder(
    make_google_token: MakeToken,
) -> None:
    """Two unlinked players both keep_current the same account: one moves it, the other then
    finds a new holder and gets a new 409 (FR-029)."""
    holder = signed_in()
    assert holder.link(make_google_token("G")).status_code == 200
    takers = [signed_in(), signed_in()]
    barrier = threading.Barrier(2)
    statuses: list[int] = []

    def take(taker: SignedIn) -> None:
        try:
            barrier.wait()
            response = taker.link(
                make_google_token("G"), resolve="keep_current", existing_player_id=holder.player_id
            )
            statuses.append(response.status_code)
        finally:
            connection.close()

    threads = [threading.Thread(target=take, args=(taker,)) for taker in takers]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert sorted(statuses) == [200, 409]
    assert Identity.objects.filter(subject="G").count() == 1
    assert str(Identity.objects.get(subject="G").player_id) in {t.player_id for t in takers}
