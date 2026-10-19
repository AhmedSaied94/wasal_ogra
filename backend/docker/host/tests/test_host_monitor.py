"""The host monitor (FR-038, contracts/operations.md "Host monitor").

`bin/host-monitor` runs under bash with stub `df`, `openssl`, `docker` and `curl` first on `PATH`.
The stubs answer from environment variables and log every ping with its body.
"""

from __future__ import annotations

import json
import os
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
HOSTS = {
    "api.1-2-3-4.sslip.io": "10.0.0.5",
    "staging-api.1-2-3-4.sslip.io": "10.0.0.5",
    "admin.10-66-0-1.sslip.io": "10.66.0.1",
    "staging-admin.10-66-0-1.sslip.io": "10.66.0.1",
}
EDGE_ENV = """PUBLIC_BIND_IP=10.0.0.5
ADMIN_BIND_IP=10.66.0.1
PUBLIC_TLS=ops@example.test
PROD_API_HOST=api.1-2-3-4.sslip.io
STAGING_API_HOST=staging-api.1-2-3-4.sslip.io
PROD_ADMIN_HOST=admin.10-66-0-1.sslip.io
STAGING_ADMIN_HOST=staging-admin.10-66-0-1.sslip.io
"""

STUB = """
import json, os, re, sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
state = Path(os.environ["STUB_DIR"])

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
    if args[:2] == ["exec", "wassal-prod-valkey-1"]:
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
        days = int(env("STUB_CERT_DAYS_" + host, "60"))
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
        log = self.stubs / "pings.jsonl"
        pings = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        log.unlink(missing_ok=True)
        return Result(result.returncode, result.stderr, pings)


@dataclass
class Result:
    code: int
    stderr: str
    pings: list[dict[str, Any]]

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
    (etc / "edge.env").write_text(EDGE_ENV)
    return Host(stubs, state, etc)


def test_all_checks_pass_with_one_ping(host: Host) -> None:
    result = host.run()

    assert result.code == 0, result.stderr
    assert result.ping["url"] == PING
    assert not result.failed


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


def test_a_certificate_near_expiry_names_its_host(host: Host) -> None:
    assert not host.run(STUB_CERT_DAYS_ADMIN_10_66_0_1_SSLIP_IO="14").failed

    result = host.run(STUB_CERT_DAYS_ADMIN_10_66_0_1_SSLIP_IO="13")

    assert result.failed
    assert "certificate admin.10-66-0-1.sslip.io expires within 14 days" in result.ping["body"]
    assert "staging-admin" not in result.ping["body"]


def test_each_host_is_checked_on_its_own_bind_address(host: Host, tmp_path: Path) -> None:
    trace = tmp_path / "trace"
    log = f'#!/usr/bin/env bash\necho "$*" >> {trace}\nexec {host.stubs / "openssl.real"} "$@"\n'
    (host.stubs / "openssl").rename(host.stubs / "openssl.real")
    (host.stubs / "openssl").write_text(log)
    (host.stubs / "openssl").chmod(0o755)

    host.run()

    connects = {
        tuple(line.split()[2:5:2]) for line in trace.read_text().splitlines() if "s_client" in line
    }
    assert connects == {(f"{ip}:443", name) for name, ip in HOSTS.items()}


def test_a_missing_certificate_fails(host: Host) -> None:
    result = host.run(STUB_NO_CERT_API_1_2_3_4_SSLIP_IO="1")

    assert result.failed
    assert "certificate api.1-2-3-4.sslip.io" in result.ping["body"]


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


def test_an_unreachable_cache_fails(host: Host) -> None:
    result = host.run(STUB_VALKEY_DOWN="1")

    assert result.failed
    assert "queues: can't read the prod cache" in result.ping["body"]


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
    result = host.run(STUB_DISK_ROOT="95", STUB_CERT_DAYS_API_1_2_3_4_SSLIP_IO="2")

    assert result.failed
    body = result.ping["body"]
    assert "disk / at 95%" in body
    assert "certificate api.1-2-3-4.sslip.io" in body


def test_a_failed_ping_exits_2(host: Host) -> None:
    result = host.run(STUB_CURL_FAIL="1")

    assert result.code == 2


def test_the_ping_url_is_required(host: Host) -> None:
    result = host.run(HC_PING_HOST_MONITOR_URL="")

    assert result.code == 2
    assert result.pings == []
