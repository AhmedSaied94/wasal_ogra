"""Verifying a callback's signature on the raw query (B07 research R1, FR-002, FR-003)."""

from __future__ import annotations

import json
from urllib.parse import quote

import pytest

from apps.ads.services import dev_signing, ssv
from apps.ads.services.ssv import SignatureInvalid
from apps.ads.tests.conftest import AdmobKeys
from apps.ads.tests.signing import signed_query


def test_a_signed_query_verifies(admob_keys: AdmobKeys) -> None:
    query, nonce = signed_query(transaction_id="t-1", user_id="u-1")
    verified = ssv.verify(query)
    assert verified.key_id == admob_keys.key_id
    assert verified.params["transaction_id"] == "t-1"
    assert verified.params["user_id"] == "u-1"
    assert json.loads(verified.params["custom_data"])["nonce"] == nonce


def test_changing_any_byte_before_the_signature_fails(admob_keys: AdmobKeys) -> None:
    query, _ = signed_query()
    message = query[: query.rfind("&signature=")]
    for index in range(0, len(message), 7):
        changed = "x" if message[index] != "x" else "y"
        tampered = query[:index] + changed + query[index + 1 :]
        with pytest.raises(SignatureInvalid):
            ssv.verify(tampered)


@pytest.mark.parametrize(
    "broken",
    [
        lambda q: q[: q.rfind("&signature=")],  # no signature
        lambda q: q[: q.rfind("&key_id=")],  # no key id
        lambda q: q[: q.rfind("&key_id=")] + "&key_id=abc",
        lambda q: q[: q.rfind("&key_id=")] + "&key_id=",
        lambda q: q.replace("&signature=", "&signature=%%%", 1),
        lambda q: q + "&extra=1",  # anything after key_id
        lambda q: q.replace("&signature=", "&signature=AAAA", 1),
        lambda q: "",
    ],
)
def test_a_broken_signature_or_key_id_fails(admob_keys: AdmobKeys, broken: object) -> None:
    query, _ = signed_query()
    with pytest.raises(SignatureInvalid):
        ssv.verify(broken(query))  # type: ignore[operator]


def test_padded_and_unpadded_signatures_verify(admob_keys: AdmobKeys) -> None:
    for _ in range(8):  # DER signatures vary in length, so some need padding
        query, _ = signed_query()
        message, _, rest = query.rpartition("&signature=")
        signature, _, key_id = rest.partition("&key_id=")
        padded = signature + "=" * (-len(signature) % 4)
        ssv.verify(query)
        ssv.verify(f"{message}&signature={padded}&key_id={key_id}")


def test_the_value_is_verified_as_sent(admob_keys: AdmobKeys) -> None:
    data = '{"placement":"morning piggy","nonce":"0b5e2f8e-6b7e-4d0b-a3c4-3c1c3f9b6a11"}'
    plus = quote(data, safe="").replace("%20", "+")
    query, _ = signed_query(raw={"custom_data": plus})
    verified = ssv.verify(query)
    assert json.loads(verified.params["custom_data"])["placement"] == "morning piggy"
    # The same value re-encoded with %20 is other bytes, which the signature doesn't cover.
    with pytest.raises(SignatureInvalid):
        ssv.verify(query.replace(plus, quote(data, safe=""), 1))


def test_an_unknown_key_refetches_once_then_fails(admob_keys: AdmobKeys) -> None:
    other = dev_signing.new_key()
    ssv.verify(signed_query()[0])
    assert admob_keys.fetches == 1
    query, _ = signed_query(key=other, key_id=99)
    with pytest.raises(SignatureInvalid):
        ssv.verify(query)
    assert admob_keys.fetches == 2


def test_a_rotated_key_is_found_by_the_refetch(admob_keys: AdmobKeys) -> None:
    ssv.verify(signed_query()[0])
    rotated = dev_signing.new_key()
    admob_keys.rotate(rotated, 77)
    ssv.verify(signed_query(key=rotated, key_id=77)[0])
    assert admob_keys.fetches == 2


def test_a_key_of_another_id_does_not_verify(admob_keys: AdmobKeys) -> None:
    rotated = dev_signing.new_key()
    admob_keys.rotate(rotated, 77)
    query, _ = signed_query(key=rotated, key_id=admob_keys.key_id)
    with pytest.raises(SignatureInvalid):
        ssv.verify(query)
