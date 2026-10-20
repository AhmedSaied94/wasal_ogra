"""One-time Backblaze B2 setup for the backups (research R9, FR-039a; B04 research R8).

Run on the operator's machine, never on the host, from `backend/`, once per environment:

    uv run tools/b2_setup.py [--env prod|staging] --daily-bucket <name> --weekly-bucket <name> \
        [--check]

It asks for the admin key (typed in, never stored or printed) and, through the B2 native API v4:

1. creates both buckets private and encrypted (SSE-B2), with Object Lock on and their lifecycle
   rule;
2. sets governance default retention, 14 and 56 days;
3. creates the environment's backup key (`writeFiles`) and, for `prod` only, the drill key
   (`listBuckets`, `listFiles`, `readFiles`), each on the two buckets and the `<env>/` prefix only.
   Staging backs itself up but is never drilled, so it has no read key;
4. signs in with each new key and checks the rights B2 reports;
5. prints the `<env>-backup.env` lines, and `prod-drill.env`'s for `prod`, once.

`--check` repeats steps 2 and 4 read-only, from the bucket and key listings, after any console
change.

`--restore-key` creates only a read key (`listBuckets`, `listFiles`, `readFiles`) on the
environment's two buckets and prefix that expires after 24 hours, and prints a temporary env file
for `restore_drill fetch` (docs/runbooks/restore.md). Staging has no read key of its own, so a
staging restore needs one; the B2 console can't make a key for two buckets.

The call sequence is provisional until the live spike (tasks.md T005) records it in research R9.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from getpass import getpass
from typing import Any
from urllib.parse import urlsplit

import requests

# Multi-bucket keys (`bucketIds`, `allowed.buckets`) exist from v4 on; v3's b2_list_keys hides them.
API_VERSION = "v4"
AUTHORIZE_URL = f"https://api.backblazeb2.com/b2api/{API_VERSION}/b2_authorize_account"
TIMEOUT_S = 30
ENVS = ("prod", "staging")
RETENTION_DAYS = {"daily": 14, "weekly": 56}
HIDDEN_DAYS_BEFORE_DELETE = 1
# Encryption at rest by B2 (SSE-B2). It guards the stored dumps, not a leaked read key.
ENCRYPTION = {"mode": "SSE-B2", "algorithm": "AES256"}
Key = tuple[str, tuple[str, ...]]  # (key name, capabilities)
RESTORE_KEY_SECONDS = 24 * 3600
BACKUP_CAPABILITIES: tuple[str, ...] = ("writeFiles",)
DRILL_CAPABILITIES: tuple[str, ...] = ("listBuckets", "listFiles", "readFiles")


@dataclass(frozen=True)
class Target:
    """One environment's backups: its object prefix and its keys, by role."""

    env: str

    @property
    def prefix(self) -> str:
        return f"{self.env}/"

    @property
    def keys(self) -> dict[str, Key]:
        keys: dict[str, Key] = {"backup": (f"wassal-{self.env}-backup", BACKUP_CAPABILITIES)}
        if self.env == "prod":  # the staging host drills production's backups only
            keys["drill"] = ("wassal-prod-drill", DRILL_CAPABILITIES)
        return keys


class SetupError(Exception):
    """A refused call or a check that failed. The message never holds a key."""


class B2:
    """The few native API calls the setup needs, signed in with one key."""

    def __init__(self, session: requests.Session, key_id: str, key: str) -> None:
        self.session = session
        response = session.get(AUTHORIZE_URL, auth=(key_id, key), timeout=TIMEOUT_S)
        auth = _payload("b2_authorize_account", response)
        storage = auth["apiInfo"]["storageApi"]
        self.account_id: str = auth["accountId"]
        self.token: str = auth["authorizationToken"]
        self.api_url: str = storage["apiUrl"]
        self.s3_url: str = storage["s3ApiUrl"]
        self.allowed: dict[str, Any] = storage["allowed"]

    def call(self, name: str, **body: Any) -> dict[str, Any]:
        response = self.session.post(
            f"{self.api_url}/b2api/{API_VERSION}/{name}",
            json={"accountId": self.account_id, **body},
            headers={"Authorization": self.token},
            timeout=TIMEOUT_S,
        )
        return _payload(name, response)


def _payload(name: str, response: requests.Response) -> dict[str, Any]:
    if not response.ok:
        try:
            code = response.json().get("code", "unknown")
        except ValueError:
            code = "unknown"
        raise SetupError(f"{name} failed: HTTP {response.status_code} {code}")
    return response.json()  # type: ignore[no-any-return]


def lifecycle(days: int) -> list[dict[str, Any]]:
    return [
        {
            "fileNamePrefix": "",
            "daysFromUploadingToHiding": days,
            "daysFromHidingToDeleting": HIDDEN_DAYS_BEFORE_DELETE,
        }
    ]


def governance(days: int) -> dict[str, Any]:
    return {"mode": "governance", "period": {"duration": days, "unit": "days"}}


def region_of(s3_url: str) -> str:
    host = urlsplit(s3_url).hostname or ""
    parts = host.split(".")
    if len(parts) != 4 or parts[0] != "s3" or parts[2:] != ["backblazeb2", "com"]:
        raise SetupError("unexpected S3 endpoint from b2_authorize_account")
    return parts[1]


# -- setup -----------------------------------------------------------------------------------------


def setup(admin: B2, session: requests.Session, target: Target, buckets: dict[str, str]) -> str:
    created: list[str] = []
    try:
        return _setup(admin, session, target, buckets, created)
    except SetupError as exc:
        if not created:
            raise
        # A half-done setup can't be re-run as is (the bucket names are taken): say what exists.
        raise SetupError(
            f"{exc}\nAlready created: {', '.join(created)}. Delete them in the B2 console (or keep "
            "the buckets and create the keys there, then run --check)."
        ) from None


def _setup(
    admin: B2,
    session: requests.Session,
    target: Target,
    buckets: dict[str, str],
    created: list[str],
) -> str:
    bucket_ids = {}
    for kind, name in buckets.items():
        bucket = admin.call(
            "b2_create_bucket",
            bucketName=name,
            bucketType="allPrivate",
            fileLockEnabled=True,
            lifecycleRules=lifecycle(RETENTION_DAYS[kind]),
            defaultServerSideEncryption=ENCRYPTION,
        )
        bucket_ids[kind] = bucket["bucketId"]
        created.append(f"bucket {name}")
    for kind, bucket_id in bucket_ids.items():
        admin.call(
            "b2_update_bucket",
            bucketId=bucket_id,
            defaultRetention=governance(RETENTION_DAYS[kind]),
        )
    ids = [bucket_ids["daily"], bucket_ids["weekly"]]
    created_keys = {}
    for role, (key_name, capabilities) in target.keys.items():
        created_keys[role] = admin.call(
            "b2_create_key",
            keyName=key_name,
            capabilities=list(capabilities),
            bucketIds=ids,
            namePrefix=target.prefix,
        )
        created.append(f"key {key_name}")
    problems = []
    for role, key in created_keys.items():
        signed_in = B2(session, key["applicationKeyId"], key["applicationKey"])
        problems += key_problems(target, role, signed_in.allowed, ids, buckets_field="buckets")
    if problems:
        raise SetupError(
            "\n".join(problems)
            + "\nDelete the new keys in the B2 console, then run the setup again."
        )
    return env_lines(target, admin.s3_url, buckets, created_keys)


def key_problems(
    target: Target,
    role: str,
    rights: dict[str, Any],
    bucket_ids: Sequence[str],
    *,
    buckets_field: str,
) -> list[str]:
    """What differs between a key's reported rights and its intended ones."""
    key_name, capabilities = target.keys[role]
    return rights_problems(
        key_name, capabilities, target.prefix, rights, bucket_ids, buckets_field=buckets_field
    )


def rights_problems(
    key_name: str,
    capabilities: Sequence[str],
    prefix: str,
    rights: dict[str, Any],
    bucket_ids: Sequence[str],
    *,
    buckets_field: str,
) -> list[str]:
    if buckets_field == "buckets":
        reported_buckets = {bucket["id"] for bucket in rights.get("buckets") or []}
    else:
        reported_buckets = set(rights.get("bucketIds") or [])
    problems = []
    if sorted(rights.get("capabilities") or []) != sorted(capabilities):
        problems.append(f"{key_name}: capabilities differ from {list(capabilities)}")
    if reported_buckets != set(bucket_ids):
        problems.append(f"{key_name}: buckets differ from the two backup buckets")
    if rights.get("namePrefix") != prefix:
        problems.append(f"{key_name}: name prefix differs from {prefix!r}")
    return problems


def env_lines(
    target: Target, s3_url: str, buckets: dict[str, str], keys: dict[str, dict[str, Any]]
) -> str:
    env = target.env
    shared = shared_lines(target, s3_url, buckets)
    backup = keys["backup"]
    lines = [
        f"# /etc/wassal/{env}-backup.env (mode 0400)",
        *shared,
        f"B2_BACKUP_KEY_ID={backup['applicationKeyId']}",
        f"B2_BACKUP_APP_KEY={backup['applicationKey']}",
        "BACKUP_WEEKLY_WEEKDAY=6",
        f"HC_PING_BACKUP_URL=<the backup-{env} ping URL>",
        "",
    ]
    if "drill" in keys:
        drill = keys["drill"]
        lines += [
            "# /etc/wassal/prod-drill.env (mode 0400)",
            *shared,
            f"B2_DRILL_KEY_ID={drill['applicationKeyId']}",
            f"B2_DRILL_APP_KEY={drill['applicationKey']}",
            "DRILL_ROWCOUNT_TOLERANCE=0",
            "HC_PING_DRILL_URL=<the restore-drill-prod ping URL>",
            "",
        ]
    return "\n".join(lines)


def shared_lines(target: Target, s3_url: str, buckets: dict[str, str]) -> list[str]:
    return [
        f"B2_S3_ENDPOINT={s3_url}",
        f"B2_REGION={region_of(s3_url)}",
        f"B2_DAILY_BUCKET={buckets['daily']}",
        f"B2_WEEKLY_BUCKET={buckets['weekly']}",
        f"BACKUP_PREFIX={target.env}",
    ]


# -- --restore-key ---------------------------------------------------------------------------------


def restore_key(
    admin: B2, session: requests.Session, target: Target, buckets: dict[str, str]
) -> str:
    """A read key on the environment's buckets and prefix that B2 expires after a day."""
    ids = []
    for name in buckets.values():
        found = admin.call("b2_list_buckets", bucketName=name)["buckets"]
        if not found:
            raise SetupError(f"{name}: bucket not found")
        ids.append(found[0]["bucketId"])
    key_name = f"wassal-{target.env}-restore"
    key = admin.call(
        "b2_create_key",
        keyName=key_name,
        capabilities=list(DRILL_CAPABILITIES),
        bucketIds=ids,
        namePrefix=target.prefix,
        validDurationInSeconds=RESTORE_KEY_SECONDS,
    )
    signed_in = B2(session, key["applicationKeyId"], key["applicationKey"])
    problems = rights_problems(
        key_name, DRILL_CAPABILITIES, target.prefix, signed_in.allowed, ids, buckets_field="buckets"
    )
    if problems:
        raise SetupError("\n".join(problems) + f"\nDelete {key_name} in the B2 console.")
    return "\n".join(
        [
            f"# /run/wassal-{target.env}-restore.env (mode 0400); the key expires in 24 h",
            *shared_lines(target, admin.s3_url, buckets),
            f"B2_DRILL_KEY_ID={key['applicationKeyId']}",
            f"B2_DRILL_APP_KEY={key['applicationKey']}",
            "",
        ]
    )


# -- --check ---------------------------------------------------------------------------------------


def check(admin: B2, target: Target, buckets: dict[str, str]) -> list[str]:
    problems = []
    bucket_ids = []
    for kind, name in buckets.items():
        found = admin.call("b2_list_buckets", bucketName=name)["buckets"]
        if not found:
            problems.append(f"{name}: bucket not found")
            continue
        bucket = found[0]
        bucket_ids.append(bucket["bucketId"])
        days = RETENTION_DAYS[kind]
        lock = (bucket.get("fileLockConfiguration") or {}).get("value") or {}
        if bucket.get("bucketType") != "allPrivate":
            problems.append(f"{name}: not private")
        if not lock.get("isFileLockEnabled"):
            problems.append(f"{name}: Object Lock is off")
        encryption = (bucket.get("defaultServerSideEncryption") or {}).get("value")
        if encryption != ENCRYPTION:
            problems.append(f"{name}: default encryption isn't SSE-B2")
        if lock.get("defaultRetention") != governance(days):
            problems.append(f"{name}: default retention isn't governance for {days} days")
        if bucket.get("lifecycleRules") != lifecycle(days):
            problems.append(f"{name}: lifecycle rule isn't hide after {days} days, delete 1 later")
    if problems:
        return problems
    listed = list_keys(admin)
    for role, (key_name, _) in target.keys.items():
        matching = [key for key in listed if key.get("keyName") == key_name]
        if len(matching) != 1:
            problems.append(f"{key_name}: expected one key with that name, found {len(matching)}")
            continue
        problems += key_problems(target, role, matching[0], bucket_ids, buckets_field="bucketIds")
    return problems


def list_keys(admin: B2) -> list[dict[str, Any]]:
    keys: list[dict[str, Any]] = []
    start: str | None = None
    while True:
        body: dict[str, Any] = {"maxKeyCount": 1000}
        if start:
            body["startApplicationKeyId"] = start
        page = admin.call("b2_list_keys", **body)
        keys += page["keys"]
        start = page.get("nextApplicationKeyId")
        if not start:
            return keys


# -- entry point -----------------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None, *, session: requests.Session | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    parser.add_argument("--env", choices=ENVS, default="prod", help="whose backups (default prod)")
    parser.add_argument("--daily-bucket", required=True)
    parser.add_argument("--weekly-bucket", required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="read-only: verify an existing setup")
    mode.add_argument(
        "--restore-key", action="store_true", help="a read key that expires in 24 h, for a restore"
    )
    args = parser.parse_args(argv)
    target = Target(args.env)
    buckets = {"daily": args.daily_bucket, "weekly": args.weekly_bucket}
    http = session or requests.Session()

    key_id = input("B2 admin key ID: ").strip()
    try:
        admin = B2(http, key_id, getpass("B2 admin application key (not echoed): "))
        if args.check:
            problems = check(admin, target, buckets)
            if problems:
                raise SetupError("\n".join(problems))
            print(
                f"ok: both buckets and {target.env}'s keys are as research R9 requires",
                file=sys.stderr,
            )
            return 0
        if args.restore_key:
            lines = restore_key(admin, http, target, buckets)
            print(
                f"Paste these into /run/wassal-{target.env}-restore.env on the {target.env} VM "
                "(restore.md). Delete the key in the B2 console once the restore is done.",
                file=sys.stderr,
            )
            print(lines)
            return 0
        lines = setup(admin, http, target, buckets)
    except SetupError as exc:
        print(f"b2_setup: {exc}", file=sys.stderr)
        return 1
    except requests.RequestException as exc:
        print(f"b2_setup: B2 unreachable ({type(exc).__name__})", file=sys.stderr)
        return 1
    print(
        "Copy these into the host's files now. The application keys are shown only once.\n"
        "Then set USD 0 caps in the B2 console (Caps & Alerts), research R9.",
        file=sys.stderr,
    )
    print(lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
