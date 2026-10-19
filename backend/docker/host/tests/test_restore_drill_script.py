"""The host restore drill script and its units (FR-040, FR-040a, contracts/operations.md
"Restore drill").

`bin/restore-drill` runs under bash with stub `docker`, `df`, `curl` and `sleep` first on `PATH`.
They log every call in order, with the contents of each `--env-file`, so the tests can check what
each container is given.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest

BASH = shutil.which("bash") or "/bin/bash"
HOST = Path(__file__).resolve().parent.parent
DRILL = HOST / "bin" / "restore-drill"
TAG = "v1.2.3"
IMAGE = f"ghcr.io/ahmedsaied94/wassal-backend:{TAG}"
POSTGRES = "postgres:17.11-trixie"
PING = "https://hc-ping.example.test/drill-uuid"
COMPACT = (",", ":")
STARTED = "2026-11-01T03:00:00Z"
PASS_LINE = json.dumps(
    {"started_at": STARTED, "outcome": "pass", "failure": None}, separators=COMPACT
)
FAIL_LINE = json.dumps(
    {"started_at": STARTED, "outcome": "fail", "failure": "row counts"}, separators=COMPACT
)
# The check container logs JSON lines to stdout too; the result line is the last one.
LOG_LINE = json.dumps({"ts": STARTED, "level": "INFO", "message": "x"}, separators=COMPACT)
DRILL_ENV = """B2_S3_ENDPOINT=https://s3.eu-central-003.backblazeb2.com
B2_REGION=eu-central-003
B2_DAILY_BUCKET=wassal-daily-x1
B2_WEEKLY_BUCKET=wassal-weekly-x1
BACKUP_PREFIX=prod
B2_DRILL_KEY_ID=drill-key-id
B2_DRILL_APP_KEY=drill-app-key-secret
DRILL_ROWCOUNT_TOLERANCE=0
HC_PING_DRILL_URL=https://hc-ping.example.test/drill-uuid
"""
THROWAWAY_KEYS = {
    "WASSAL_ENV",
    "SECRET_KEY",
    "DATABASE_URL",
    "CACHE_URL",
    "CELERY_BROKER_URL",
    "API_HOST",
    "ADMIN_HOST",
    "SENTRY_DSN",
    "HC_PING_HEARTBEAT_URL",
}

STUB = """
import json, os, sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
state = Path(os.environ["STUB_DIR"])
call = {"cmd": name, "args": args}
if name == "docker":
    files = [args[i + 1] for i, a in enumerate(args) if a == "--env-file"]
    call["env_files"] = {f: Path(f).read_text() for f in files}
if name == "curl":
    config = Path(args[args.index("-K") + 1]).read_text()
    call["url"] = config.split('"')[1]
    call["body"] = sys.stdin.read()
    call["results_written"] = Path(os.environ["WASSAL_STATE_DIR"], "drill-results.jsonl").exists()
with open(state / "calls.jsonl", "a") as log:
    log.write(json.dumps(call) + "\\n")

def fail(step):
    return os.environ.get("STUB_FAIL") == step

if name in ("sleep", "curl"):
    sys.exit(0)
if name == "df":
    print("Avail")
    print(f" {os.environ.get('STUB_FREE_GB', '40')}G")
    sys.exit(0)
# docker
if args[0] == "info":
    print("/var/lib/docker")
elif args[:2] == ["network", "create"]:
    sys.exit(1 if fail("network") else 0)
elif args[:2] == ["volume", "create"]:
    sys.exit(1 if fail("volume") else 0)
elif args[0] == "run" and "-d" in args:
    sys.exit(1 if fail("database") else 0)
elif args[0] == "exec":
    sys.exit(1 if fail("ready") else 0)
elif args[0] == "run" and "fetch" in args:
    sys.exit(1 if fail("fetch") else 0)
elif args[0] == "run" and "check" in args:
    sys.stdout.write(os.environ.get("STUB_CHECK_OUTPUT", "{}\\n"))
    sys.exit(int(os.environ.get("STUB_CHECK_EXIT", "0")))
"""


@dataclass
class Result:
    code: int
    stderr: str
    calls: list[dict[str, Any]] = field(default_factory=list)

    def docker(self, *prefix: str) -> list[list[str]]:
        n = len(prefix)
        return [
            c["args"] for c in self.calls if c["cmd"] == "docker" and tuple(c["args"][:n]) == prefix
        ]

    def run_of(self, word: str) -> dict[str, Any]:
        [call] = [
            c
            for c in self.calls
            if c["cmd"] == "docker" and c["args"][0] == "run" and word in c["args"]
        ]
        return call

    @property
    def pings(self) -> list[dict[str, Any]]:
        return [c for c in self.calls if c["cmd"] == "curl"]

    @property
    def ping(self) -> dict[str, Any]:
        [ping] = self.pings
        return ping

    @property
    def ping_url(self) -> str:
        assert not any("hc-ping" in a for a in self.ping["args"]), "the URL is on argv"
        return str(self.ping["url"])

    def steps(self) -> list[str]:
        """Each call as a short step name, in order."""
        names = []
        for call in self.calls:
            args = call["args"]
            if call["cmd"] == "docker":
                if args[0] == "run":
                    names.append(
                        "fetch" if "fetch" in args else "check" if "check" in args else "database"
                    )
                elif args[0] in ("network", "volume"):
                    names.append(f"{args[0]} {args[1]}")
                else:
                    names.append(args[0])
            elif call["cmd"] in ("df", "curl"):
                names.append(call["cmd"])
        return names


@dataclass
class Host:
    root: Path

    @property
    def state(self) -> Path:
        return self.root / "state"

    @property
    def stubs(self) -> Path:
        return self.root / "stubs"

    @property
    def drill_dir(self) -> Path:
        return self.state / "drill"

    @property
    def results(self) -> Path:
        return self.state / "drill-results.jsonl"

    def run(self, *args: str, **stub_env: str) -> Result:
        env = {
            "PATH": f"{self.stubs}:{os.environ['PATH']}",
            "STUB_DIR": str(self.stubs),
            "WASSAL_STATE_DIR": str(self.state),
            "WASSAL_ETC": str(self.root / "etc"),
            "WASSAL_APP_UID": str(os.getuid()),
            "WASSAL_APP_GID": str(os.getgid()),
            "TMPDIR": str(self.root / "tmp"),
            "HC_PING_DRILL_URL": PING,
            "DRILL_ROWCOUNT_TOLERANCE": "0",
            "STUB_CHECK_OUTPUT": f"{LOG_LINE}\n{PASS_LINE}\n",
            "WASSAL_DRILL_READY_ATTEMPTS": "3",
            **stub_env,
        }
        result = subprocess.run(  # noqa: S603 - fixed script and arguments
            [BASH, str(DRILL), *(args or ("prod",))],
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
        log = self.stubs / "calls.jsonl"
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        log.unlink(missing_ok=True)
        return Result(result.returncode, result.stderr, calls)


@pytest.fixture
def host(tmp_path: Path) -> Host:
    host = Host(tmp_path)
    host.stubs.mkdir()
    for name in ("docker", "df", "curl", "sleep"):
        stub = host.stubs / name
        stub.write_text(f"#!{sys.executable}\n{STUB}")
        stub.chmod(0o755)
    (tmp_path / "tmp").mkdir()
    (tmp_path / "etc").mkdir()
    (tmp_path / "etc" / "prod-drill.env").write_text(DRILL_ENV)
    stack = host.state / "prod" / "deploy" / TAG
    (stack / "env").mkdir(parents=True)
    (stack / "compose.yml").write_text(
        f"services:\n  api:\n    image: ghcr.io/x:1\n  postgres:\n    image: {POSTGRES}\n"
    )
    (host.state / "prod" / "release").write_text(TAG)
    return host


def env_file(call: dict[str, Any], *, skip: str = "") -> dict[str, str]:
    """The variables a `docker run` call passes through its env files, except the one named."""
    values: dict[str, str] = {}
    for path, text in call["env_files"].items():
        if skip and path.endswith(skip):
            continue
        for line in text.splitlines():
            key, _, value = line.partition("=")
            values[key] = value
    return values


# -- a passing drill -------------------------------------------------------------------------------


def test_the_steps_run_in_order(host: Host) -> None:
    result = host.run()

    assert result.code == 0, result.stderr
    assert result.steps() == [
        "info",
        "df",
        "rm",
        "volume rm",
        "network rm",
        "fetch",
        "network create",
        "volume create",
        "database",
        "exec",
        "check",
        "curl",
        "rm",
        "volume rm",
        "network rm",
    ]
    assert result.ping["results_written"] is True


def test_fetch_runs_on_the_default_bridge_with_the_drill_key(host: Host) -> None:
    result = host.run()

    fetch = result.run_of("fetch")
    args = fetch["args"]
    assert args[args.index("--network") + 1] == "bridge"
    assert args.count("--network") == 1
    assert f"{host.drill_dir}:/drill" in args
    assert args[-6:] == [IMAGE, "python", "manage.py", "restore_drill", "fetch", "/drill"]
    assert str(host.root / "etc" / "prod-drill.env") in fetch["env_files"]
    assert set(env_file(fetch, skip="prod-drill.env")) == THROWAWAY_KEYS


def test_the_database_is_internal_capped_and_on_prods_postgres_tag(host: Host) -> None:
    result = host.run()

    assert result.docker("network", "create") == [
        ["network", "create", "--internal", "wassal-drill"]
    ]
    assert result.docker("volume", "create") == [["volume", "create", "wassal-drill-pgdata"]]
    database = result.run_of("-d")
    args = database["args"]
    assert args[args.index("--name") + 1] == "wassal-drill-db"
    assert args[args.index("--network") + 1] == "wassal-drill"
    assert args[args.index("--memory") + 1] == "1g"
    assert "wassal-drill-pgdata:/var/lib/postgresql/data" in args
    assert args[-1] == POSTGRES
    password = env_file(database)["POSTGRES_PASSWORD"]
    assert len(password) >= 32


def test_check_gets_only_the_drill_network_and_throwaway_values(host: Host) -> None:
    result = host.run()

    check = result.run_of("check")
    args = check["args"]
    assert args[args.index("--network") + 1] == "wassal-drill"
    assert args.count("--network") == 1
    assert f"{host.drill_dir}:/drill:ro" in args
    assert args[-6:] == [IMAGE, "python", "manage.py", "restore_drill", "check", "/drill"]
    values = env_file(check)
    assert set(values) == THROWAWAY_KEYS | {"DRILL_ROWCOUNT_TOLERANCE"}
    assert not any("prod-drill.env" in path for path in check["env_files"])
    assert "drill-app-key-secret" not in json.dumps(check)
    assert values["WASSAL_ENV"] == "prod"
    assert values["CACHE_URL"] == "locmem://"
    assert values["CELERY_BROKER_URL"] == "memory://"
    assert values["API_HOST"] == values["ADMIN_HOST"] == "drill.invalid"
    assert values["SENTRY_DSN"] == "https://drill@drill.invalid/1"
    assert values["HC_PING_HEARTBEAT_URL"] == "https://drill.invalid/"
    password = env_file(result.run_of("-d"))["POSTGRES_PASSWORD"]
    assert values["DATABASE_URL"] == f"postgres://postgres:{password}@wassal-drill-db:5432/postgres"
    assert len(values["SECRET_KEY"]) == 64


def test_each_run_has_new_secrets(host: Host) -> None:
    first, second = host.run(), host.run()

    for word, key in (("check", "SECRET_KEY"), ("-d", "POSTGRES_PASSWORD")):
        assert env_file(first.run_of(word))[key] != env_file(second.run_of(word))[key]


def test_the_result_line_is_kept_and_pinged(host: Host) -> None:
    result = host.run()

    assert host.results.read_text() == PASS_LINE + "\n"
    assert result.ping_url == PING
    assert result.ping["body"].strip() == PASS_LINE
    host.run()
    assert host.results.read_text().splitlines() == [PASS_LINE, PASS_LINE]


def test_the_drill_directory_is_removed(host: Host) -> None:
    host.run()

    assert not host.drill_dir.exists()
    assert list((host.root / "tmp").iterdir()) == []


# -- failures --------------------------------------------------------------------------------------


def test_a_failed_outcome_is_kept_and_pings_fail(host: Host) -> None:
    result = host.run(STUB_CHECK_OUTPUT=f"{FAIL_LINE}\n{LOG_LINE}\n", STUB_CHECK_EXIT="1")

    assert result.code == 1
    assert host.results.read_text() == FAIL_LINE + "\n"
    assert result.ping_url == f"{PING}/fail"
    assert result.ping["body"].strip() == FAIL_LINE


def test_low_disk_pings_fail_and_starts_nothing(host: Host) -> None:
    result = host.run(STUB_FREE_GB="4")

    assert result.code == 1
    assert result.steps() == ["info", "df", "curl"]
    assert result.ping_url == f"{PING}/fail"
    assert "4 GB free" in result.ping["body"]
    assert not host.results.exists()


@pytest.mark.parametrize("step", ["fetch", "network", "volume", "database", "ready"])
def test_a_failed_step_still_cleans_up_and_pings_fail(host: Host, step: str) -> None:
    result = host.run(STUB_FAIL=step)

    assert result.code == 1
    assert result.steps()[-4:] == ["curl", "rm", "volume rm", "network rm"]
    assert result.docker("rm")[-1] == ["rm", "-f", "wassal-drill-db"]
    assert result.docker("volume", "rm")[-1] == ["volume", "rm", "wassal-drill-pgdata"]
    assert result.docker("network", "rm")[-1] == ["network", "rm", "wassal-drill"]
    assert result.ping_url == f"{PING}/fail"
    assert not host.drill_dir.exists()
    assert "check" not in result.steps()


@pytest.mark.parametrize(
    "output", ["", "Traceback (most recent call last):\n", "{not json}\n", f"{LOG_LINE}\n"]
)
def test_a_check_with_no_result_pings_fail(host: Host, output: str) -> None:
    result = host.run(STUB_CHECK_OUTPUT=output, STUB_CHECK_EXIT="2")

    assert result.code == 1
    assert result.ping_url == f"{PING}/fail"
    assert "printed no result" in result.ping["body"]
    assert not host.results.exists()


def test_a_pass_line_with_a_failing_exit_is_no_result(host: Host) -> None:
    result = host.run(STUB_CHECK_EXIT="1")

    assert result.code == 1
    assert "printed no result (exit 1)" in result.ping["body"]
    assert not host.results.exists()


def test_the_drill_containers_are_hardened(host: Host) -> None:
    result = host.run()

    for word in ("fetch", "check"):
        args = result.run_of(word)["args"]
        assert args[args.index("--cap-drop") + 1] == "ALL"
        assert args[args.index("--security-opt") + 1] == "no-new-privileges"
        assert "--pids-limit" in args
    database = result.run_of("-d")["args"]
    assert database[database.index("--security-opt") + 1] == "no-new-privileges"
    assert "--pids-limit" in database


def test_the_ping_url_is_required(host: Host) -> None:
    result = host.run(HC_PING_DRILL_URL="")

    assert result.code == 2
    assert result.calls == []


@pytest.mark.parametrize("args", [("dev",), ("prod", "extra")])
def test_bad_arguments_exit_2(host: Host, args: tuple[str, ...]) -> None:
    result = host.run(*args)

    assert result.code == 2
    assert result.calls == []


def test_a_bad_tolerance_is_refused(host: Host) -> None:
    result = host.run(DRILL_ROWCOUNT_TOLERANCE="-1")

    assert result.code == 2
    assert result.calls == []


# -- units -----------------------------------------------------------------------------------------


def unit(name: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (HOST / "systemd" / name).read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key] = value
    return values


def test_the_timer_runs_on_the_first_at_five_cairo_time() -> None:
    timer = unit("wassal-restore-drill@.timer")

    assert timer["OnCalendar"] == "*-*-01 05:00:00 Africa/Cairo"
    assert timer["Persistent"] == "true"
    assert timer["WantedBy"] == "timers.target"


def test_the_service_reads_the_drill_env_file() -> None:
    service = unit("wassal-restore-drill@.service")

    assert service["ExecStart"] == "/opt/wassal/bin/restore-drill %i"
    assert service["EnvironmentFile"] == "/etc/wassal/%i-drill.env"
    assert service["ConditionPathExists"] == "/etc/wassal/%i-drill.env"
    assert service["Type"] == "oneshot"
