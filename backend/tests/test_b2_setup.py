"""`tools/b2_setup.py`, the one-time B2 setup (research R9).

A fake `requests.Session` plays the B2 native API (v4): it records every call and answers like B2
does. The call sequence is provisional until the live spike (T005) records the real one.
"""

from __future__ import annotations

import copy
from typing import Any

import pytest

from tools import b2_setup

ADMIN_ID = "admin-key-id"
ADMIN_KEY = "admin-application-key-never-printed"
ACCOUNT = "acct-1"
API_URL = "https://api003.backblazeb2.com"
S3_URL = "https://s3.eu-central-003.backblazeb2.com"
DAILY = "wassal-daily-x1"
WEEKLY = "wassal-weekly-x1"
ARGS = ["--daily-bucket", DAILY, "--weekly-bucket", WEEKLY]


class Response:
    def __init__(self, status: int, payload: dict[str, Any]) -> None:
        self.status_code = status
        self.ok = status < 400
        self._payload = payload

    def json(self) -> dict[str, Any]:
        return copy.deepcopy(self._payload)


class FakeB2:
    """Buckets and keys in memory, with each call recorded as `(api name, request body)`."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self.buckets: dict[str, dict[str, Any]] = {}
        self.keys: dict[str, dict[str, Any]] = {}
        # keyId -> what b2_authorize_account reports, when it should differ from the key's record.
        self.reported: dict[str, dict[str, Any]] = {}
        self.errors: dict[str, tuple[int, str]] = {}

    # -- requests.Session ---------------------------------------------------------------------

    def get(self, url: str, *, auth: tuple[str, str], timeout: float) -> Response:
        assert url == "https://api.backblazeb2.com/b2api/v4/b2_authorize_account"
        assert timeout > 0
        key_id, key = auth
        self.calls.append(("b2_authorize_account", {"keyId": key_id}))
        if key_id == ADMIN_ID and key == ADMIN_KEY:
            allowed: dict[str, Any] = {"capabilities": ["all"], "buckets": None, "namePrefix": None}
        elif key_id in self.keys and self.keys[key_id]["applicationKey"] == key:
            record = self.keys[key_id]
            allowed = {
                "capabilities": record["capabilities"],
                "buckets": [
                    {"id": bucket_id, "name": self.bucket_name(bucket_id)}
                    for bucket_id in record["bucketIds"]
                ],
                "namePrefix": record["namePrefix"],
            } | self.reported.get(key_id, {})
        else:
            return Response(401, {"status": 401, "code": "unauthorized", "message": "bad key"})
        return Response(
            200,
            {
                "accountId": ACCOUNT,
                "authorizationToken": f"token-{key_id}",
                "apiInfo": {
                    "storageApi": {"apiUrl": API_URL, "s3ApiUrl": S3_URL, "allowed": allowed}
                },
            },
        )

    def post(
        self, url: str, *, json: dict[str, Any], headers: dict[str, str], timeout: float
    ) -> Response:
        prefix = f"{API_URL}/b2api/v4/"
        assert url.startswith(prefix)
        assert headers["Authorization"].startswith("token-")
        assert timeout > 0
        name = url.removeprefix(prefix)
        self.calls.append((name, copy.deepcopy(json)))
        if name in self.errors:
            status, code = self.errors[name]
            return Response(status, {"status": status, "code": code, "message": "refused"})
        assert json["accountId"] == ACCOUNT
        return Response(200, getattr(self, name)(copy.deepcopy(json)))

    # -- the B2 calls -------------------------------------------------------------------------

    def bucket_name(self, bucket_id: str) -> str:
        return next(name for name, b in self.buckets.items() if b["bucketId"] == bucket_id)

    def b2_create_bucket(self, body: dict[str, Any]) -> dict[str, Any]:
        bucket = {
            "accountId": ACCOUNT,
            "bucketId": f"id-{body['bucketName']}",
            "bucketName": body["bucketName"],
            "bucketType": body["bucketType"],
            "lifecycleRules": body.get("lifecycleRules", []),
            "defaultServerSideEncryption": {
                "isClientAuthorizedToRead": True,
                "value": body.get("defaultServerSideEncryption") or {"mode": None},
            },
            "fileLockConfiguration": {
                "isClientAuthorizedToRead": True,
                "value": {
                    "isFileLockEnabled": bool(body.get("fileLockEnabled")),
                    "defaultRetention": {"mode": None, "period": None},
                },
            },
        }
        self.buckets[body["bucketName"]] = bucket
        return bucket

    def b2_update_bucket(self, body: dict[str, Any]) -> dict[str, Any]:
        bucket = self.buckets[self.bucket_name(body["bucketId"])]
        bucket["fileLockConfiguration"]["value"]["defaultRetention"] = body["defaultRetention"]
        return bucket

    def b2_list_buckets(self, body: dict[str, Any]) -> dict[str, Any]:
        found = [b for name, b in self.buckets.items() if name == body.get("bucketName", name)]
        return {"buckets": found}

    def b2_create_key(self, body: dict[str, Any]) -> dict[str, Any]:
        key_id = f"keyid-{body['keyName']}"
        record = {
            "accountId": ACCOUNT,
            "applicationKeyId": key_id,
            "applicationKey": f"secret-{body['keyName']}",
            "keyName": body["keyName"],
            "capabilities": body["capabilities"],
            "bucketIds": body["bucketIds"],
            "namePrefix": body["namePrefix"],
        }
        self.keys[key_id] = record
        return record

    def b2_list_keys(self, body: dict[str, Any]) -> dict[str, Any]:
        keys = [{k: v for k, v in r.items() if k != "applicationKey"} for r in self.keys.values()]
        return {"keys": keys, "nextApplicationKeyId": None}


@pytest.fixture
def b2(monkeypatch: pytest.MonkeyPatch) -> FakeB2:
    fake = FakeB2()
    monkeypatch.setattr("builtins.input", lambda prompt="": ADMIN_ID)
    monkeypatch.setattr(b2_setup, "getpass", lambda prompt="": ADMIN_KEY)
    return fake


def names(b2: FakeB2) -> list[str]:
    return [name for name, _ in b2.calls]


def bodies(b2: FakeB2, name: str) -> list[dict[str, Any]]:
    return [body for call, body in b2.calls if call == name]


def run(b2: FakeB2, *extra: str) -> int:
    return b2_setup.main([*ARGS, *extra], session=b2)  # type: ignore[arg-type]


# -- setup -----------------------------------------------------------------------------------------


def test_setup_follows_the_call_sequence(b2: FakeB2) -> None:
    assert run(b2) == 0

    assert names(b2) == [
        "b2_authorize_account",
        "b2_create_bucket",
        "b2_create_bucket",
        "b2_update_bucket",
        "b2_update_bucket",
        "b2_create_key",
        "b2_create_key",
        "b2_authorize_account",
        "b2_authorize_account",
    ]


def test_both_buckets_are_private_locked_and_expire(b2: FakeB2) -> None:
    run(b2)

    daily, weekly = bodies(b2, "b2_create_bucket")
    for body, name, days in ((daily, DAILY, 14), (weekly, WEEKLY, 56)):
        assert body["bucketName"] == name
        assert body["bucketType"] == "allPrivate"
        assert body["fileLockEnabled"] is True
        assert body["defaultServerSideEncryption"] == {"mode": "SSE-B2", "algorithm": "AES256"}
        assert body["lifecycleRules"] == [
            {"fileNamePrefix": "", "daysFromUploadingToHiding": days, "daysFromHidingToDeleting": 1}
        ]


def test_governance_retention_is_14_and_56_days(b2: FakeB2) -> None:
    run(b2)

    daily, weekly = bodies(b2, "b2_update_bucket")
    assert daily["bucketId"] == f"id-{DAILY}"
    assert daily["defaultRetention"] == {
        "mode": "governance",
        "period": {"duration": 14, "unit": "days"},
    }
    assert weekly["bucketId"] == f"id-{WEEKLY}"
    assert weekly["defaultRetention"] == {
        "mode": "governance",
        "period": {"duration": 56, "unit": "days"},
    }


def test_the_keys_have_exactly_their_capabilities(b2: FakeB2) -> None:
    run(b2)

    backup, drill = bodies(b2, "b2_create_key")
    both = [f"id-{DAILY}", f"id-{WEEKLY}"]
    assert backup["capabilities"] == ["writeFiles"]
    assert drill["capabilities"] == ["listBuckets", "listFiles", "readFiles"]
    for key in (backup, drill):
        assert key["bucketIds"] == both
        assert key["namePrefix"] == "prod/"
        assert "validDurationInSeconds" not in key


def test_each_new_key_is_checked_by_signing_in_with_it(b2: FakeB2) -> None:
    run(b2)

    signed_in = [body["keyId"] for body in bodies(b2, "b2_authorize_account")]
    assert signed_in == [ADMIN_ID, "keyid-wassal-prod-backup", "keyid-wassal-prod-drill"]


@pytest.mark.parametrize(
    "reported",
    [
        {"capabilities": ["writeFiles", "deleteFiles"]},
        {"buckets": [{"id": f"id-{DAILY}", "name": DAILY}]},
        {"namePrefix": None},
    ],
)
def test_a_key_that_reports_other_rights_fails(
    b2: FakeB2, capsys: pytest.CaptureFixture[str], reported: dict[str, Any]
) -> None:
    b2.reported["keyid-wassal-prod-backup"] = reported

    assert run(b2) != 0

    out, err = capsys.readouterr()
    assert "wassal-prod-backup" in err
    assert "secret-wassal-prod" not in out + err


def test_the_env_lines_are_printed_once(b2: FakeB2, capsys: pytest.CaptureFixture[str]) -> None:
    run(b2)

    out, err = capsys.readouterr()
    assert out.count("B2_BACKUP_APP_KEY=secret-wassal-prod-backup") == 1
    assert out.count("B2_DRILL_APP_KEY=secret-wassal-prod-drill") == 1
    assert "B2_BACKUP_KEY_ID=keyid-wassal-prod-backup" in out
    assert "B2_DRILL_KEY_ID=keyid-wassal-prod-drill" in out
    assert out.count(f"B2_S3_ENDPOINT={S3_URL}") == 2
    assert out.count("B2_REGION=eu-central-003") == 2
    assert out.count(f"B2_DAILY_BUCKET={DAILY}") == 2
    assert "secret-wassal-prod" not in err


def test_the_admin_key_is_typed_in_and_never_printed(
    b2: FakeB2, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    prompts: list[str] = []

    def typed(prompt: str = "") -> str:
        prompts.append(prompt)
        return ADMIN_KEY

    monkeypatch.setattr(b2_setup, "getpass", typed)

    run(b2)

    out, err = capsys.readouterr()
    assert len(prompts) == 1
    assert ADMIN_KEY not in out + err


def test_a_refused_call_stops_with_its_error_code(
    b2: FakeB2, capsys: pytest.CaptureFixture[str]
) -> None:
    b2.errors["b2_create_bucket"] = (400, "duplicate_bucket_name")

    assert run(b2) != 0

    _, err = capsys.readouterr()
    assert "b2_create_bucket" in err
    assert "duplicate_bucket_name" in err
    assert "b2_create_key" not in names(b2)
    assert ADMIN_KEY not in err


def test_a_half_done_setup_says_what_it_created(
    b2: FakeB2, capsys: pytest.CaptureFixture[str]
) -> None:
    b2.errors["b2_create_key"] = (400, "too_many_keys")

    assert run(b2) != 0

    err = capsys.readouterr().err
    assert "too_many_keys" in err
    assert f"Already created: bucket {DAILY}, bucket {WEEKLY}." in err


def test_a_wrong_admin_key_stops_early(b2: FakeB2, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(b2_setup, "getpass", lambda prompt="": "wrong")

    assert run(b2) != 0
    assert names(b2) == ["b2_authorize_account"]


# -- --check ---------------------------------------------------------------------------------------

WRITES = {"b2_create_bucket", "b2_update_bucket", "b2_create_key", "b2_delete_key"}


def test_check_passes_after_setup_and_writes_nothing(
    b2: FakeB2, capsys: pytest.CaptureFixture[str]
) -> None:
    run(b2)
    b2.calls.clear()
    capsys.readouterr()

    assert run(b2, "--check") == 0

    assert not WRITES & set(names(b2))
    out, _ = capsys.readouterr()
    assert "APP_KEY" not in out


def test_check_reports_a_shortened_retention(
    b2: FakeB2, capsys: pytest.CaptureFixture[str]
) -> None:
    run(b2)
    retention = b2.buckets[WEEKLY]["fileLockConfiguration"]["value"]["defaultRetention"]
    retention["period"]["duration"] = 14
    capsys.readouterr()

    assert run(b2, "--check") != 0

    _, err = capsys.readouterr()
    assert WEEKLY in err
    assert "retention" in err


def test_check_reports_a_bucket_without_encryption(
    b2: FakeB2, capsys: pytest.CaptureFixture[str]
) -> None:
    run(b2)
    b2.buckets[DAILY]["defaultServerSideEncryption"]["value"] = {"mode": None}
    capsys.readouterr()

    assert run(b2, "--check") != 0
    assert "SSE-B2" in capsys.readouterr().err


def test_check_reports_a_changed_lifecycle(b2: FakeB2, capsys: pytest.CaptureFixture[str]) -> None:
    run(b2)
    b2.buckets[DAILY]["lifecycleRules"] = []
    capsys.readouterr()

    assert run(b2, "--check") != 0
    assert "lifecycle" in capsys.readouterr().err


def test_check_reports_a_key_with_extra_rights(
    b2: FakeB2, capsys: pytest.CaptureFixture[str]
) -> None:
    run(b2)
    b2.keys["keyid-wassal-prod-drill"]["capabilities"].append("deleteFiles")
    capsys.readouterr()

    assert run(b2, "--check") != 0
    assert "wassal-prod-drill" in capsys.readouterr().err


def test_check_reports_a_missing_bucket(b2: FakeB2, capsys: pytest.CaptureFixture[str]) -> None:
    assert run(b2, "--check") != 0

    assert not WRITES & set(names(b2))
    assert DAILY in capsys.readouterr().err
