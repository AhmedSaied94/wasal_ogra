"""AdMob's server-side verification callback (B07 research R1, R4-R6, R13; data-model.md).

`verify` checks the ECDSA signature on the raw query string, before anything touches the database.
`process` then records the callback, idempotent on `transaction_id`, and grants the morning piggy
when every check passes, in one transaction:

    another publisher's ad unit, or no usable transaction id (answered, logged, not recorded) →
    duplicate transaction id →
    malformed → expired → unattributed → not_server_placement → (the wallet lock) →
    duplicate_reference → cap_reached → granted

The amounts and the cap come from one live-settings snapshot, never from the callback (FR-011).
A grant writes one `ssv_grant` ledger entry per non-zero amount and moves `state_version`, as a
staff adjustment does. Nothing signed can make the database refuse the row: over-long text is cut
to its column and unparseable numbers are stored as 0 or NULL, so AdMob never sees a 500.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import logging
import re
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import parse_qs

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.accounts.models import Player
from apps.ads.models import AdReward
from apps.ads.services import keys
from apps.common.ids import uuid7
from apps.economy.models import Currency, LedgerEntry
from apps.economy.services import ledger
from apps.economy.services import settings as economy_settings
from apps.economy.services.gameday import game_date
from apps.liveops import settings as live

logger = logging.getLogger("apps.ads")

Outcome = AdReward.Outcome
# Answered 200 and logged, with no new row: the transaction id was already recorded.
DUPLICATE = "duplicate"
# The only placement the server grants (glossary §3.4); the others are the phone's, through sync.
SERVER_PLACEMENTS = frozenset({"morning_piggy"})
# Answered 200 and logged, with no row: signed by Google, but for another publisher's ad unit.
FOREIGN_AD_UNIT = "foreign_ad_unit"
# FR-006a: older callbacks are refused, so a replay after the cleanup grants nothing.
EXPIRY_DAYS = 7
# Google stamps the callback; one dated further ahead than this is not a real one.
FUTURE_DAYS = 1
MAX_TRANSACTION_ID = 128
INT32 = 2**31 - 1
# Where an empty `ADS_ALLOWED_AD_UNITS` lets every ad unit through (the tests' own key).
OPEN_AD_UNIT_ENVIRONMENTS = ("dev", "test")
# No PostgreSQL text column stores NUL, and no lone surrogate encodes to UTF-8.
_UNSTORABLE = re.compile("[\x00\ud800-\udfff]")
# AdMob's last two parameters, nothing after them (research R1).
_TAIL = re.compile(r"signature=([A-Za-z0-9_-]+={0,2})&key_id=(\d{1,18})")
_SIGNATURE_MARK = "&signature="
_LENGTHS = {"custom_data": 512, "ad_unit": 64, "reward_item": 64, "ad_network": 32}


# Refusals of a well-formed signed tail: what the operator's alert counts. A bare GET from a
# scanner (no signature, a broken tail) is refused too, but doesn't use the alert's hourly slot.
FORGED = frozenset({"signature", "unknown key", "repeated parameter"})


class SignatureInvalid(Exception):
    """No signature, a signature that doesn't verify, or a key Google doesn't publish."""


@dataclass(frozen=True)
class VerifiedQuery:
    params: dict[str, str]
    key_id: int


def verify(raw_query: str) -> VerifiedQuery:
    """The parameters of a validly signed query. Raises `SignatureInvalid`, and lets
    `keys.KeysUnavailable` through."""
    cut = raw_query.rfind(_SIGNATURE_MARK)
    if cut < 0:
        raise SignatureInvalid("unsigned")
    message, tail = raw_query[:cut], raw_query[cut + 1 :]
    match = _TAIL.fullmatch(tail)
    if match is None:
        raise SignatureInvalid("tail")
    encoded, key_id = match.group(1).rstrip("="), int(match.group(2))
    try:
        signature = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
    except (binascii.Error, ValueError):
        raise SignatureInvalid("encoding") from None
    key = keys.public_key(key_id)
    if key is None:
        raise SignatureInvalid("unknown key")
    try:
        key.verify(signature, message.encode(), ec.ECDSA(hashes.SHA256()))
    except (InvalidSignature, ValueError):
        raise SignatureInvalid("signature") from None
    parsed = parse_qs(message, keep_blank_values=True)
    if any(len(values) != 1 for values in parsed.values()):
        raise SignatureInvalid("repeated parameter")  # AdMob sends each name once
    return VerifiedQuery({name: values[0] for name, values in parsed.items()}, key_id)


def _our_ad_unit(ad_unit: str) -> bool:
    """Google's verifier keys sign every publisher's callbacks, so the signature alone doesn't
    say the ad was ours: only `ADS_ALLOWED_AD_UNITS` grants (security review H1)."""
    allowed = settings.ADS_ALLOWED_AD_UNITS
    if not allowed:
        return settings.WASSAL_ENV in OPEN_AD_UNIT_ENVIRONMENTS
    return ad_unit in allowed


@dataclass
class _Parsed:
    """The row's values, and whether any of them was unusable."""

    fields: dict[str, Any]
    malformed: bool
    placement: str
    nonce: uuid.UUID | None
    user_id: str


def process(raw_query: str, *, now: datetime | None = None) -> str:
    """Verify, record and maybe grant. Returns the outcome (or `DUPLICATE`) for the log only:
    the caller answers every validly signed callback with the same 200."""
    verified = verify(raw_query)
    now = now or timezone.now()
    params = verified.params
    transaction_id = params.get("transaction_id", "")
    if not _our_ad_unit(params.get("ad_unit", "")):
        _log(FOREIGN_AD_UNIT, verified, transaction_id)
        return FOREIGN_AD_UNIT
    if (
        not transaction_id
        or len(transaction_id) > MAX_TRANSACTION_ID
        or _UNSTORABLE.search(transaction_id)
    ):
        _log(Outcome.MALFORMED, verified, transaction_id)
        return str(Outcome.MALFORMED)
    parsed = _parse(params, verified.key_id)
    for _ in range(2):  # a second pass only after losing a race on the reference
        try:
            outcome = _record(transaction_id, parsed, now)
        except IntegrityError:
            if AdReward.objects.filter(transaction_id=transaction_id).exists():
                outcome = DUPLICATE
            else:
                continue  # another callback took the reference: decide again
        _log(outcome, verified, transaction_id)
        return outcome
    raise RuntimeError("an ad reward could not be recorded")  # pragma: no cover


def _record(transaction_id: str, parsed: _Parsed, now: datetime) -> str:
    with transaction.atomic():
        if AdReward.objects.filter(transaction_id=transaction_id).exists():
            return DUPLICATE
        reward_id = uuid7()
        row: dict[str, Any] = {
            **parsed.fields,
            "id": reward_id,
            "transaction_id": transaction_id,
            "game_date": game_date(now),
            "created_at": now,
        }
        refusal, player = _refusal_before_lock(parsed, now)
        if refusal is not None:
            outcome = refusal
        elif player is not None:
            outcome = _decide_and_grant(player, parsed, row, reward_id, now)
            if outcome == DUPLICATE:
                return DUPLICATE
        else:  # pragma: no cover - a pass needs a player
            outcome = Outcome.UNATTRIBUTED
        if outcome in (Outcome.MALFORMED, Outcome.DUPLICATE_REFERENCE):
            row["nonce"] = None
        elif (
            row["nonce"] is not None
            and outcome != Outcome.GRANTED
            and AdReward.objects.filter(nonce=row["nonce"]).exists()
        ):
            row["nonce"] = None  # a refusal never takes a reference another row holds (R5)
        AdReward.objects.create(outcome=outcome, player=player, **row)
        return str(outcome)


def _refusal_before_lock(parsed: _Parsed, now: datetime) -> tuple[str | None, Player | None]:
    """The cheap refusals, before any player row is locked (research R4)."""
    callback_at = parsed.fields["callback_at"]
    if parsed.malformed or callback_at - now > timedelta(days=FUTURE_DAYS):
        return Outcome.MALFORMED, None
    if now - callback_at > timedelta(days=EXPIRY_DAYS):
        return Outcome.EXPIRED, _active_player(parsed.user_id)
    player = _active_player(parsed.user_id)
    if player is None:
        return Outcome.UNATTRIBUTED, None
    if parsed.placement not in SERVER_PLACEMENTS:
        return Outcome.NOT_SERVER_PLACEMENT, player
    return None, player


def _decide_and_grant(
    player: Player, parsed: _Parsed, row: dict[str, Any], reward_id: uuid.UUID, now: datetime
) -> str:
    """Under the wallet lock, the lock sync takes: the reference, the cap, the grant."""
    snapshot = live.current()
    wallet = ledger.lock_wallet(player, now=now, config=economy_settings.from_snapshot(snapshot))
    if AdReward.objects.filter(transaction_id=row["transaction_id"]).exists():
        return DUPLICATE  # delivered twice at once; the first holder of the lock recorded it
    if AdReward.objects.filter(nonce=parsed.nonce).exists():
        return str(Outcome.DUPLICATE_REFERENCE)
    granted_today = AdReward.objects.filter(
        player=player,
        placement=parsed.placement,
        game_date=row["game_date"],
        outcome=Outcome.GRANTED,
    ).count()
    if granted_today >= snapshot["ads_morning_piggy_daily_cap"]:
        return str(Outcome.CAP_REACHED)
    amounts = {
        Currency.JENEHAT: snapshot["ads_morning_piggy_jenehat"],
        Currency.BONAT: snapshot["ads_morning_piggy_bonat"],
    }
    for currency, amount in amounts.items():
        if amount > 0:  # the ledger refuses a zero entry
            ledger.apply_now(
                wallet,
                currency=currency,
                delta=amount,
                reason=LedgerEntry.Reason.SSV_GRANT,
                source=LedgerEntry.Source.SSV,
                ref_type="ad_reward",
                ref_id=str(reward_id),
            )
    wallet.state_version += 1
    wallet.save(update_fields=["state_version", "updated_at"])
    row["jenehat"] = amounts[Currency.JENEHAT]
    row["bonat"] = amounts[Currency.BONAT]
    return str(Outcome.GRANTED)


def _active_player(user_id: str) -> Player | None:
    try:
        pk = uuid.UUID(user_id)
    except ValueError:
        return None
    player = Player.objects.filter(pk=pk).first()
    return player if player is not None and player.is_active else None


def _parse(params: dict[str, str], key_id: int) -> _Parsed:
    malformed = False
    fields: dict[str, Any] = {"key_id": key_id}
    for name, length in _LENGTHS.items():
        value = params.get(name, "")
        if len(value) > length or _UNSTORABLE.search(value):
            malformed = True
        fields[name] = _UNSTORABLE.sub("", value)[:length]

    amount = _integer(params.get("reward_amount", ""))
    if amount is None or not -INT32 - 1 <= amount <= INT32:
        malformed, amount = True, 0
    fields["reward_amount"] = amount

    millis = _integer(params.get("timestamp", ""))
    callback_at = None
    if millis is not None:
        try:
            callback_at = datetime.fromtimestamp(millis / 1000, tz=UTC)
        except (OverflowError, OSError, ValueError):
            callback_at = None
    if callback_at is None:
        malformed = True
    fields["callback_at"] = callback_at

    placement, nonce = "", None
    raw = params.get("custom_data", "")
    try:
        data = json.loads(raw) if len(raw) <= _LENGTHS["custom_data"] else None
    except ValueError:
        data = None
    if isinstance(data, dict) and isinstance(data.get("placement"), str):
        placement = data["placement"]
        if _UNSTORABLE.search(placement):
            malformed, placement = True, _UNSTORABLE.sub("", placement)
        placement = placement[:32]
        try:
            nonce = uuid.UUID(str(data.get("nonce")))
        except ValueError:
            nonce = None
    if nonce is None:
        malformed = True
    fields["placement"] = placement
    fields["nonce"] = nonce
    return _Parsed(fields, malformed, placement, nonce, params.get("user_id", ""))


def _integer(value: str) -> int | None:
    """A plain decimal integer: no sign, space, underscore or fraction."""
    if not value or not value.isascii() or not value.isdigit() or len(value) > 19:
        return None
    return int(value)


def _log(outcome: str, verified: VerifiedQuery, transaction_id: str) -> None:
    """One line per callback, naming neither the player nor the reference (FR-007, R13)."""
    params = verified.params
    logger.info(
        "ad_ssv_callback",
        extra={
            "outcome": outcome,
            "key_id": verified.key_id,
            "ad_unit": params.get("ad_unit", "")[:64],
            "reward_item": params.get("reward_item", "")[:64],
            "transaction": hashlib.sha256(transaction_id.encode()).hexdigest()[:12],
        },
    )
