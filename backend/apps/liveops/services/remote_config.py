"""The daily Remote Config drift check (B10 research R8, FR-009).

Reads Firebase Remote Config's client template with a read-only service account (PyJWT signs the
assertion, `requests` exchanges it), compares every phone-applied setting, records one row and sends
Sentry one warning when a setting both sides apply differs. The key and the token never reach a log
line, an exception message or Sentry.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta
from typing import Any

import jwt
import requests
import sentry_sdk
from django.conf import settings as django_settings
from django.utils import timezone

from apps.liveops import registry
from apps.liveops import settings as live
from apps.liveops.models import RemoteConfigCheck

logger = logging.getLogger("apps.liveops")

SCOPE = "https://www.googleapis.com/auth/firebase.remoteconfig"
TOKEN_URL = "https://oauth2.googleapis.com/token"  # noqa: S105 - an endpoint, not a secret
TEMPLATE_URL = "https://firebaseremoteconfig.googleapis.com/v1/projects/{project}/remoteConfig"
TIMEOUT_SECONDS = 10
TOKEN_LIFETIME_SECONDS = 3600
ATTEMPTS = 3
KEEP = timedelta(days=90)
FINGERPRINT = ["liveops", "remote-config-drift"]


class RemoteConfigError(RuntimeError):
    """A failed step, named without its URL, body or credential."""


def configured() -> bool:
    return bool(
        django_settings.FIREBASE_PROJECT_ID and django_settings.REMOTE_CONFIG_SERVICE_ACCOUNT
    )


def fetch_token(account: dict[str, Any], *, now: datetime | None = None) -> str:
    """Sign the service account's assertion and exchange it for an access token (one hour)."""
    at = now or timezone.now()
    issued = int(at.timestamp())
    claims = {
        "iss": account["client_email"],
        "scope": SCOPE,
        "aud": TOKEN_URL,
        "iat": issued,
        "exp": issued + TOKEN_LIFETIME_SECONDS,
    }
    assertion = jwt.encode(
        claims,
        account["private_key"],
        algorithm="RS256",
        headers={"kid": account.get("private_key_id", "")},
    )
    response = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        },
        timeout=TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    return str(response.json()["access_token"])


def fetch_template(project_id: str, token: str) -> dict[str, Any]:
    response = requests.get(
        TEMPLATE_URL.format(project=project_id),
        headers={"Authorization": f"Bearer {token}"},
        timeout=TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    body: dict[str, Any] = response.json()
    return body


def _account() -> dict[str, Any]:
    raw = django_settings.REMOTE_CONFIG_SERVICE_ACCOUNT
    try:
        account: dict[str, Any] = json.loads(raw)
    except ValueError:
        raise RemoteConfigError("service account is not JSON") from None
    if not account.get("client_email") or not account.get("private_key"):
        raise RemoteConfigError("service account is missing its email or key")
    return account


def _fetch(project_id: str, account: dict[str, Any]) -> dict[str, Any]:
    return fetch_template(project_id, fetch_token(account))


def run(*, now: datetime | None = None) -> RemoteConfigCheck:
    """One run: compare, record, alert. A network failure retries, then records `unreachable`."""
    at = now or timezone.now()
    RemoteConfigCheck.objects.filter(ran_at__lt=at - KEEP).delete()
    if not configured():
        return _record(at, RemoteConfigCheck.Status.NOT_CONFIGURED, "", [])
    project_id = django_settings.FIREBASE_PROJECT_ID
    try:
        account = _account()
    except RemoteConfigError as error:
        logger.warning("remote_config_unusable", extra={"reason": str(error)})
        return _record(at, RemoteConfigCheck.Status.UNREACHABLE, "", [])
    template: dict[str, Any] | None = None
    for attempt in range(1, ATTEMPTS + 1):
        try:
            template = _fetch(project_id, account)
        except requests.RequestException as error:
            logger.warning(
                "remote_config_unreachable",
                extra={"attempt": attempt, "reason": type(error).__name__},
            )
            continue
        break
    if template is None:
        return _record(at, RemoteConfigCheck.Status.UNREACHABLE, "", [])
    drift = compare(template)
    version = str(template.get("version", {}).get("versionNumber", ""))[:32]
    status = RemoteConfigCheck.Status.DRIFT if drift else RemoteConfigCheck.Status.OK
    row = _record(at, status, version, drift)
    if any(entry["applied_by"] == registry.BOTH for entry in drift):
        sentry_sdk.capture_message(
            "Remote Config drift",
            level="warning",
            fingerprint=FINGERPRINT,
            extras={"drift": drift},
        )
    return row


def compare(template: dict[str, Any]) -> list[dict[str, Any]]:
    """Every phone-applied setting whose Remote Config default differs from the server's."""
    parameters = template.get("parameters") or {}
    snapshot = live.current()
    drift: list[dict[str, Any]] = []
    for spec in registry.SPECS.values():
        if spec.applied_by == registry.SERVER:
            continue
        remote = _remote_value(spec, parameters.get(spec.key))
        server = snapshot[spec.key]
        if remote != server:
            drift.append(
                {
                    "key": spec.key,
                    "server": server,
                    "remote_config": remote,
                    "applied_by": spec.applied_by,
                }
            )
    return drift


def _remote_value(spec: registry.Spec, parameter: Any) -> Any:
    """The template's default, or the bundled default when the app uses its own (R8)."""
    if not isinstance(parameter, dict):
        return spec.default
    default = parameter.get("defaultValue")
    if not isinstance(default, dict) or "value" not in default:
        return spec.default
    raw = default["value"]
    try:
        return registry.validate(spec, _parse(spec, raw))
    except ValueError:
        return raw  # a template value that doesn't parse is a drift worth seeing


def _parse(spec: registry.Spec, raw: Any) -> Any:
    if spec.kind == registry.INT and isinstance(raw, str):
        return int(raw)
    if spec.kind == registry.BOOL and isinstance(raw, str):
        return raw.strip().lower() in ("1", "true", "yes", "on")
    return raw


def _record(
    at: datetime, status: str, version: str, drift: list[dict[str, Any]]
) -> RemoteConfigCheck:
    row = RemoteConfigCheck.objects.create(
        ran_at=at, status=status, template_version=version, drift=drift
    )
    if status == RemoteConfigCheck.Status.DRIFT:
        logger.warning("remote_config_drift", extra={"keys": [entry["key"] for entry in drift]})
    return row


def latest_marks() -> dict[str, Any]:
    """The drift list of the latest run that compared anything, for the admin's column."""
    row = (
        RemoteConfigCheck.objects.filter(
            status__in=(RemoteConfigCheck.Status.OK, RemoteConfigCheck.Status.DRIFT)
        )
        .order_by("-ran_at", "-id")
        .first()
    )
    if row is None or not row.drift:
        return {}
    marks: dict[str, Any] = {}
    for entry in row.drift:
        if isinstance(entry, dict) and "key" in entry:
            marks[entry["key"]] = entry
    return marks
