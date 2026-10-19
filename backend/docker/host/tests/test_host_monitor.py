"""The host monitor (FR-038, contracts/operations.md "Host monitor").

`bin/host-monitor` runs under bash with stub `df`, `openssl`, `docker` and `curl` first on `PATH`.
The stubs answer from environment variables, log every call, and log every ping with its body.

Each host runs its own monitor for its own environment, named in `host.env`: the prod host by
default here, the staging host with `host.as_staging()`.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

BASH = shutil.which("bash") or "/bin/bash"
MONITOR = Path(__file__).resolve().parent.parent / "bin" / "host-monitor"
PING = "https://hc-ping.example.test/host-monitor-uuid"
API = "api.193-122-74-125.sslip.io"
ADMIN = "admin.10-66-0-1.sslip.io"
STAGING_API = "staging-api.141-147-129-92.sslip.io"
STAGING_ADMIN = "staging-admin.10-67-0-1.sslip.io"
HOST_ENV = {"prod": "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\n"}
HOST_ENV["staging"] = "WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\n"
EDGE_ENV = {
    "prod": f"""PUBLIC_BIND_IP=10.0.0.28
ADMIN_BIND_IP=10.66.0.1
PUBLIC_TLS=ops@example.test
API_HOST={API}
ADMIN_HOST={ADMIN}
""",
    "staging": f"""PUBLIC_BIND_IP=10.1.0.216
ADMIN_BIND_IP=10.67.0.1
PUBLIC_TLS=ops@example.test
API_HOST={STAGING_API}
ADMIN_HOST={STAGING_ADMIN}
""",
}
DAY = 86400


def key(prefix: str, name: str) -> str:
    """The stub variable for one host name or queue, as the stub spells it."""
    return prefix + re.sub(r"[^A-Za-z0-9]", "_", name).upper()


STUB = """
import json, os, re, sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
state = Path(os.environ["STUB_DIR"])
with open(state / "calls.jsonl", "a") as log:
    log.write(json.dumps({"cmd": name, "args": args}) + "\\n")

def env(key, default=None):
    return os.environ.get(re.sub(r"[^A-Za-z0-9]", "_", key).upper(), default)

if name == "curl":
    body = sys.stdin.read() if "--data-binary" in args else ""
    # The URL comes in a curl config, never on argv.
    assert not any(a.startswith("https://") for a in args), "the URL is on argv"
    url = Path(args[args.index("-K") + 1]).read_text().split('"')[1]
    with open(state / "pings.jsonl", "a") as log:
        log.write(json.dumps({"url": url, "body": body}) + "\\n")
    sys.exit(7 if os.environ.get("STUB_CURL_FAIL") else 0)
if name == "df":
    path = args[-1]
    print("Use%")
    print(f" {env('STUB_DISK_' + ('ROOT' if path == '/' else 'DOCKER'), '42')}%")
    sys.exit(0)
if name == "docker":
    if args[:1] == ["info"]:
        print("/var/lib/docker")
        sys.exit(0)
    if args[0] == "exec" and re.fullmatch(r"wassal-(prod|staging)-valkey-1", args[1]):
        if os.environ.get("STUB_VALKEY_DOWN"):
            sys.exit(1)
        print(env("STUB_QUEUE_" + args[-1], "0"))
        sys.exit(0)
if name == "openssl":
    if args[0] == "s_client":
        host = args[args.index("-servername") + 1]
        address = args[args.index("-connect") + 1]
        if env("STUB_NO_CERT_" + host):
            sys.exit(1)
        print(f"-----BEGIN CERTIFICATE-----\\nHOST:{host}@{address}\\n-----END CERTIFICATE-----")
        sys.exit(0)
    if args[0] == "x509":
        host = re.search(r"HOST:([^@]+)@", sys.stdin.read()).group(1)
        # Days left on the certificate; 0.5 is Caddy's 12-hour internal one, < 0 expired.
        days = float(env("STUB_CERT_DAYS_" + host, "60"))
        seconds = int(args[args.index("-checkend") + 1])
        sys.exit(1 if days * 86400 < seconds else 0)
sys.exit(f"stub {name}: unexpected {args}")
"""


@dataclass
class Host:
    stubs: Path
    state: Path
    etc: Path

    def backlog(self, **first_seen: int) -> None:
        (self.state / "host-monitor" / "backlog.json").write_text(json.dumps(first_seen))

    def as_staging(self) -> Host:
        (self.etc / "host.env").write_text(HOST_ENV["staging"])
        (self.etc / "edge.env").write_text(EDGE_ENV["staging"])
        return self

    def read_backlog(self) -> dict[str, int]:
        return json.loads((self.state / "host-monitor" / "backlog.json").read_text())  # type: ignore[no-any-return]

    def run(self, **stub_env: str) -> Result:
        env = {
            "PATH": f"{self.stubs}:{os.environ['PATH']}",
            "STUB_DIR": str(self.stubs),
            "WASSAL_STATE_DIR": str(self.state),
            "WASSAL_ETC": str(self.etc),
            "HC_PING_HOST_MONITOR_URL": PING,
            "DISK_ALERT_PERCENT": "80",
            "CERT_ALERT_DAYS": "14",
            "QUEUE_BACKLOG_THRESHOLD": "100",
            "QUEUE_BACKLOG_MINUTES": "10",
            "BACKUP_STORAGE_ALERT_BYTES": "8000000000",
            **stub_env,
        }
        result = subprocess.run(  # noqa: S603 - fixed script and arguments
            [BASH, str(MONITOR)], env=env, capture_output=True, text=True, check=False, timeout=60
        )
        logs = {}
        for name in ("pings", "calls"):
            log = self.stubs / f"{name}.jsonl"
            logs[name] = (
                [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            )
            log.unlink(missing_ok=True)
        return Result(result.returncode, result.stderr, logs["pings"], logs["calls"])


@dataclass
class Result:
    code: int
    stderr: str
    pings: list[dict[str, Any]]
    calls: list[dict[str, Any]]

    def args_of(self, cmd: str, first: str) -> list[list[str]]:
        return [c["args"] for c in self.calls if c["cmd"] == cmd and c["args"][:1] == [first]]

    @property
    def connects(self) -> set[tuple[str, str]]:
        """The (address, SNI name) each certificate was read from."""
        return {
            (args[args.index("-connect") + 1], args[args.index("-servername") + 1])
            for args in self.args_of("openssl", "s_client")
        }

    @property
    def ping(self) -> dict[str, Any]:
        [ping] = self.pings
        return ping

    @property
    def failed(self) -> bool:
        return bool(self.ping["url"] == f"{PING}/fail")


@pytest.fixture
def host(tmp_path: Path) -> Host:
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    for name in ("df", "openssl", "docker", "curl"):
        stub = stubs / name
        stub.write_text(f"#!{sys.executable}\n{STUB}")
        stub.chmod(0o755)
    state = tmp_path / "state"
    (state / "host-monitor").mkdir(parents=True)
    (state / "prod" / "backup").mkdir(parents=True)
    etc = tmp_path / "etc"
    etc.mkdir()
    (etc / "host.env").write_text(HOST_ENV["prod"])
    (etc / "edge.env").write_text(EDGE_ENV["prod"])
    return Host(stubs, state, etc)


def test_all_checks_pass_with_one_ping(host: Host) -> None:
    result = host.run()

    assert result.code == 0, result.stderr
    assert result.ping["url"] == PING
    assert not result.failed
    assert result.ping["body"].strip() == "ok: disk, certificates, queues, backup storage"


def test_staging_runs_its_checks_without_backup_storage(host: Host) -> None:
    host.as_staging()
    last = host.state / "prod" / "backup" / "last-backup.json"
    last.write_text(json.dumps({"size_bytes": 900_000_000_000, "sha256": "x"}))

    result = host.run()

    assert result.code == 0, result.stderr
    assert not result.failed
    # The body names the checks that ran, so a skipped one never reads as passed.
    assert result.ping["body"].strip() == "ok: disk, certificates, queues"


def test_disk_at_the_threshold_fails(host: Host) -> None:
    assert not host.run(STUB_DISK_ROOT="79").failed

    result = host.run(STUB_DISK_ROOT="80")

    assert result.code == 1
    assert result.failed
    assert "disk / at 80%" in result.ping["body"]


def test_the_docker_data_root_is_checked_too(host: Host) -> None:
    result = host.run(STUB_DISK_DOCKER="91")

    assert result.failed
    assert "disk /var/lib/docker at 91%" in result.ping["body"]


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_the_api_certificate_alerts_14_days_ahead(host: Host, env: str) -> None:
    api = API if env == "prod" else STAGING_API
    if env == "staging":
        host.as_staging()
    assert not host.run(**{key("STUB_CERT_DAYS_", api): "14"}).failed

    result = host.run(**{key("STUB_CERT_DAYS_", api): "13"})

    assert result.code == 1
    assert result.failed
    assert result.ping["body"].strip() == f"certificate {api} expires within 14 days"


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_the_admin_certificate_only_has_to_be_valid_now(host: Host, env: str) -> None:
    admin = ADMIN if env == "prod" else STAGING_ADMIN
    if env == "staging":
        host.as_staging()
    # Caddy's local CA issues it for 12 hours and renews it itself.
    assert not host.run(**{key("STUB_CERT_DAYS_", admin): "0.5"}).failed

    result = host.run(**{key("STUB_CERT_DAYS_", admin): "-0.01"})

    assert result.failed
    assert result.ping["body"].strip() == f"certificate {admin} has expired"


def test_the_api_check_uses_cert_alert_days_and_the_admin_check_now(host: Host) -> None:
    result = host.run(CERT_ALERT_DAYS="20")

    ends = [args[args.index("-checkend") + 1] for args in result.args_of("openssl", "x509")]
    assert sorted(ends) == sorted([str(20 * DAY), "0"])


@pytest.mark.parametrize(
    ("env", "expected"),
    [
        ("prod", {("10.0.0.28:443", API), ("10.66.0.1:443", ADMIN)}),
        ("staging", {("10.1.0.216:443", STAGING_API), ("10.67.0.1:443", STAGING_ADMIN)}),
    ],
)
def test_each_name_is_read_from_its_own_bind_address(
    host: Host, env: str, expected: set[tuple[str, str]]
) -> None:
    if env == "staging":
        host.as_staging()

    result = host.run()

    assert result.connects == expected


@pytest.mark.parametrize("name", [API, ADMIN])
def test_a_missing_certificate_fails(host: Host, name: str) -> None:
    result = host.run(**{key("STUB_NO_CERT_", name): "1"})

    assert result.failed
    assert f"certificate {name}: couldn't be read" in result.ping["body"]


@pytest.mark.parametrize("name", ["API_HOST", "ADMIN_HOST", "PUBLIC_BIND_IP", "ADMIN_BIND_IP"])
def test_a_name_missing_from_edge_env_fails(host: Host, name: str) -> None:
    kept = [line for line in EDGE_ENV["prod"].splitlines() if not line.startswith(f"{name}=")]
    (host.etc / "edge.env").write_text("\n".join(kept) + "\n")

    result = host.run()

    assert result.failed
    assert f"certificates: {name} is missing from edge.env" in result.ping["body"]


def test_the_one_host_names_are_not_read(host: Host) -> None:
    (host.etc / "edge.env").write_text(
        "PUBLIC_BIND_IP=10.0.0.28\nADMIN_BIND_IP=10.66.0.1\n"
        f"PROD_API_HOST={API}\nPROD_ADMIN_HOST={ADMIN}\n"
    )

    result = host.run()

    assert result.failed
    assert result.connects == set()


def test_a_queue_backlog_alerts_after_ten_minutes(host: Host) -> None:
    now = int(time.time())

    first = host.run(STUB_QUEUE_PUSH="101")
    assert not first.failed
    seen = host.read_backlog()["push"]
    assert now - 5 <= seen <= now + 5

    host.backlog(push=now - 9 * 60)
    assert not host.run(STUB_QUEUE_PUSH="150").failed
    assert host.read_backlog()["push"] == now - 9 * 60

    host.backlog(push=now - 10 * 60)
    result = host.run(STUB_QUEUE_PUSH="150")
    assert result.failed
    assert "queue push has 150 messages" in result.ping["body"]


def test_the_backlog_resets_when_the_queue_drains(host: Host) -> None:
    host.backlog(push=int(time.time()) - 30 * 60, content=int(time.time()))

    result = host.run(STUB_QUEUE_PUSH="100", STUB_QUEUE_CONTENT="300")

    assert not result.failed
    assert list(host.read_backlog()) == ["content"]


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_the_queues_are_this_hosts_environments(host: Host, env: str) -> None:
    if env == "staging":
        host.as_staging()

    result = host.run(STUB_QUEUE_CONTENT="300")

    containers = {args[1] for args in result.args_of("docker", "exec")}
    assert containers == {f"wassal-{env}-valkey-1"}
    assert sorted(args[-1] for args in result.args_of("docker", "exec")) == sorted(
        ["default", "purchases", "content", "push"]
    )
    assert list(host.read_backlog()) == ["content"]


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_an_unreachable_cache_fails(host: Host, env: str) -> None:
    if env == "staging":
        host.as_staging()

    result = host.run(STUB_VALKEY_DOWN="1")

    assert result.failed
    assert f"queues: can't read the {env} cache" in result.ping["body"]


def test_backup_storage_near_the_free_tier_fails(host: Host) -> None:
    last = host.state / "prod" / "backup" / "last-backup.json"
    last.write_text(json.dumps({"size_bytes": 300_000_000, "sha256": "x"}))
    assert not host.run().failed

    last.write_text(json.dumps({"size_bytes": 400_000_000, "sha256": "x"}))
    result = host.run()

    assert result.failed
    assert "backup-storage:" in result.ping["body"]


@pytest.mark.parametrize("size", ['"12"', "0099", "99999999999999", "-5"])
def test_a_size_that_isnt_a_plain_number_fails(host: Host, size: str) -> None:
    last = host.state / "prod" / "backup" / "last-backup.json"
    last.write_text('{"size_bytes": ' + size + ', "sha256": "x"}')

    result = host.run()

    assert result.failed
    assert "has no valid size_bytes" in result.ping["body"]


def test_several_failures_are_listed_together(host: Host) -> None:
    result = host.run(STUB_DISK_ROOT="95", **{key("STUB_CERT_DAYS_", API): "2"})

    assert result.failed
    body = result.ping["body"]
    assert "disk / at 95%" in body
    assert f"certificate {API}" in body


def test_a_failed_ping_exits_2(host: Host) -> None:
    result = host.run(STUB_CURL_FAIL="1")

    assert result.code == 2


def test_the_ping_url_is_required(host: Host) -> None:
    result = host.run(HC_PING_HOST_MONITOR_URL="")

    assert result.code == 2
    assert result.pings == []


# -- the host's environment ------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        None,
        "",
        "WASSAL_ENV=prod\n",
        "WG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=dev\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=prod\nWG_ADDRESS=10.67.0.1\n",
        "WASSAL_ENV=staging\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=prod\nWASSAL_ENV=staging\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=Prod\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\n\n",
        "# the prod host\nWASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\n",
        "export WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\nOTHER=1\n",
        'WASSAL_ENV="prod"\nWG_ADDRESS=10.66.0.1\n',
        "WASSAL_ENV=prod\r\nWG_ADDRESS=10.66.0.1\r\n",
        "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\nWG_ADDRESS=10.66.0.1\n",
    ],
)
def test_a_missing_or_unknown_environment_exits_2_without_a_ping(
    host: Host, text: str | None
) -> None:
    path = host.etc / "host.env"
    if text is None:
        path.unlink()
    else:
        path.write_text(text)

    result = host.run()

    assert result.code == 2
    assert result.pings == []
    assert result.calls == []
    assert "host.env" in result.stderr


def test_host_env_is_read_as_data_never_sourced(host: Host, tmp_path: Path) -> None:
    marker = tmp_path / "sourced"
    (host.etc / "host.env").write_text(
        f"WASSAL_ENV=prod$(touch {marker})\nWG_ADDRESS=10.66.0.1\ntouch {marker}\n"
    )

    result = host.run()

    assert result.code == 2
    assert not marker.exists()
