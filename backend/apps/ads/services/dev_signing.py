"""Signing callbacks as AdMob does, with a key of our own: the tests and `ads_dev_callback` only.

AdMob sends its parameters in a fixed order, URL-encodes each value, and signs everything before
`&signature=` with ECDSA P-256 and SHA-256. The signature is DER in URL-safe base64 without
padding, followed by `&key_id=` (research R1). Nothing on the request path imports this module.
"""

from __future__ import annotations

import base64
import json
import time
import uuid
from typing import Any
from urllib.parse import quote

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

# The order AdMob sends them in (its SSV documentation).
ORDER = (
    "ad_network",
    "ad_unit",
    "custom_data",
    "reward_amount",
    "reward_item",
    "timestamp",
    "transaction_id",
    "user_id",
)
DEFAULT_KEY_ID = 3_335_741_209


def new_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


def key_entry(key: ec.EllipticCurvePrivateKey, key_id: int) -> dict[str, Any]:
    """One entry of AdMob's key list: `keyId`, `pem` and `base64` (the DER, standard base64)."""
    public = key.public_key()
    pem = public.public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    der = public.public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    return {"keyId": key_id, "pem": pem.decode(), "base64": base64.b64encode(der).decode()}


def custom_data(placement: str = "morning_piggy", nonce: str | None = None) -> str:
    """The app's `customData`: compact JSON (research "Handed to later features", M11)."""
    return json.dumps(
        {"placement": placement, "nonce": nonce or str(uuid.uuid4())}, separators=(",", ":")
    )


def sign(message: str, key: ec.EllipticCurvePrivateKey) -> str:
    der = key.sign(message.encode(), ec.ECDSA(hashes.SHA256()))
    return base64.urlsafe_b64encode(der).decode().rstrip("=")


def signed_query(
    key: ec.EllipticCurvePrivateKey,
    *,
    key_id: int = DEFAULT_KEY_ID,
    raw: dict[str, str] | None = None,
    **params: Any,
) -> tuple[str, str]:
    """A signed query string and the reference (`nonce`) in its `custom_data`.

    Keyword values replace the defaults; `None` drops a parameter. `raw` gives already-encoded
    values, sent as they are (`+` for a space, say).
    """
    nonce = str(params.pop("nonce", None) or uuid.uuid4())
    placement = params.pop("placement", "morning_piggy")
    values: dict[str, Any] = {
        "ad_network": "5450213213286189855",
        "ad_unit": "1234567890",
        "custom_data": custom_data(placement, nonce),
        "reward_amount": "1",
        "reward_item": "piggy",
        "timestamp": str(int(time.time() * 1000)),
        "transaction_id": uuid.uuid4().hex,
        "user_id": str(uuid.uuid4()),
    }
    values.update(params)
    raw = raw or {}
    parts = []
    for name in ORDER:
        if name in raw:
            parts.append(f"{name}={raw[name]}")
        elif values.get(name) is not None:
            parts.append(f"{name}={quote(str(values[name]), safe='')}")
    message = "&".join(parts)
    return f"{message}&signature={sign(message, key)}&key_id={key_id}", nonce
