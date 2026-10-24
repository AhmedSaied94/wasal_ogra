"""SC-007: no email, name, picture, raw install id or token is stored or logged (research R14).

100 players sign in, link a Google account whose token carries a unique email, name and picture,
renew once, and one more player meets a conflict. Then every text column of every table, and every
log record captured at DEBUG, is searched for each of those values.
"""

from __future__ import annotations

import json
import logging

import pytest
from django.db import connection

from apps.accounts.tests.conftest import MakeToken, signed_in
from apps.accounts.tests.factories import renew

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("no_throttle", "google_jwks")]

PLAYERS = 100
TEXT_TYPES = ("text", "character varying", "character", "json", "jsonb")


def text_columns() -> list[tuple[str, str]]:
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT table_name, column_name FROM information_schema.columns"
            " WHERE table_schema = current_schema() AND data_type = ANY(%s)"
            " ORDER BY table_name, column_name",
            [list(TEXT_TYPES)],
        )
        return [(table, column) for table, column in cursor.fetchall()]


def stored(values: list[str]) -> list[str]:
    """`table.column: value` for each value found inside any text column."""
    found: list[str] = []
    quote = connection.ops.quote_name
    with connection.cursor() as cursor:
        for table, column in text_columns():
            # Names come from information_schema and are quoted; the values are parameters.
            cursor.execute(
                f"SELECT s FROM unnest(%s::text[]) AS s WHERE EXISTS ("  # noqa: S608
                f" SELECT 1 FROM {quote(table)} AS t WHERE strpos(t.{quote(column)}::text, s) > 0)",
                [values],
            )
            found += [f"{table}.{column}: {value[:40]}" for (value,) in cursor.fetchall()]
    return found


def logged(records: list[logging.LogRecord], values: list[str]) -> list[str]:
    texts = [
        record.getMessage() + json.dumps(record.__dict__, default=str, ensure_ascii=False)
        for record in records
    ]
    return [value[:40] for value in values if any(value in text for text in texts)]


def test_nothing_personal_is_stored_or_logged(
    make_google_token: MakeToken, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    secrets: list[str] = []
    subjects: list[str] = []
    for n in range(PLAYERS):
        player = signed_in()
        subject = f"1000000000000000{n:05d}"
        claims = {
            "email": f"privacy.{n}@example.test",
            "name": f"Privacy Person {n}",
            "picture": f"https://lh3.example.test/a/privacy-{n}.png",
        }
        google_token = make_google_token(subject, **claims)
        assert player.link(google_token).status_code == 200
        renewed = renew(player.client, player.refresh).json()
        secrets += [*claims.values(), str(player.install), google_token]
        secrets += [player.access, player.refresh, renewed["access"], renewed["refresh"]]
        subjects.append(subject)
    other = signed_in()
    clash = {"email": "clash@example.test", "name": "Privacy Clash"}
    conflict = make_google_token(subjects[0], **clash)
    assert other.link(conflict).status_code == 409
    secrets += [*clash.values(), conflict, str(other.install), other.access]

    # The scan finds what is stored: Google's subject is kept (research R6), so it must show up.
    assert stored(subjects[:1]) == [f"accounts_identity.subject: {subjects[0]}"]
    assert stored(secrets) == []
    assert logged(caplog.records, secrets) == []
    assert caplog.records, "nothing was captured, so the log check proves nothing"
