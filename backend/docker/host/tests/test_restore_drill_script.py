"""The host restore drill script and its units (FR-040, FR-040a, contracts/operations.md
"Restore drill").

`bin/restore-drill` runs under bash with stub `docker`, `df`, `curl` and `sleep` first on `PATH`.
They log every call in order, with the contents of each `--env-file`, so the tests can check what
each container is given. The stub fetch writes `backup.json`, and the stub `docker cp` writes the
check image's `compose.yml`.

The drill runs on the staging host: it fetches with staging's serving image, then checks with the
production release that took the backup.
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
REPO = "ghcr.io/ahmedsaied94/wassal-backend"
# Staging's serving release fetches; the release that took the backup checks.
STAGING_TAG = "sha-" + "5a" * 20
FETCH_IMAGE = f"{REPO}:{STAGING_TAG}"
RELEASE = "0123456789abcdef" * 2 + "01234567"
CHECK_IMAGE = f"{REPO}:sha-{RELEASE}"
# The check image's own compose file names production's database for that release. Staging's
# serving stack names another one, which the drill must not use.
POSTGRES = "postgres:17.9-trixie"
STAGING_POSTGRES = "postgres:18.1-trixie"
COPIER = "wassal-drill-copy"
HOST_ENV = "WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\n"
PING = "https://hc-ping.example.test/drill-uuid"
COMPACT = (",", ":")
STARTED = "2026-11-01T03:00:00Z"
PASS_LINE = json.dumps(
    {"started_at": STARTED, "release": RELEASE, "outcome": "pass", "failure": None},
    separators=COMPACT,
)
FAIL_LINE = json.dumps(
    {"started_at": STARTED, "release": RELEASE, "outcome": "fail", "failure": "row counts"},
    separators=COMPACT,
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


def compose(postgres: str) -> str:
    return f"services:\n  api:\n    image: {REPO}:x\n  postgres:\n    image: {postgres}\n"


def metadata(**fields: object) -> str:
    """`backup.json` as `restore_drill fetch` writes it."""
    meta: dict[str, object] = {
        "schema_version": 1,
        "environment": "prod",
        "created_at": "2026-11-01T01:00:12Z",
        "release": RELEASE,
        "dump": {"key": "prod/2026/11/01/prod-20261101T010012Z.dump", "size_bytes": 1},
        "tables": {"public.release": 3},
        **fields,
    }
    return json.dumps({k: v for k, v in meta.items() if v is not None}, indent=2) + "\n"


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
    if fail("fetch"):
        sys.exit(1)
    drill = next(a for a in args if a.endswith(":/drill")).removesuffix(":/drill")
    Path(drill, "backup.json").write_text(os.environ["STUB_BACKUP_JSON"])
elif args[0] == "pull":
    sys.exit(1 if fail("pull") else 0)
elif args[0] == "create":
    if fail("create"):
        sys.exit(1)
    print("0123abcd")
elif args[0] == "cp":
    if fail("cp"):
        sys.exit(1)
    Path(args[2]).write_text(os.environ["STUB_COMPOSE"])
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
            "STUB_BACKUP_JSON": metadata(),
            "STUB_COMPOSE": compose(POSTGRES),
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
    (tmp_path / "etc" / "host.env").write_text(HOST_ENV)
    stack = host.state / "staging" / "deploy" / STAGING_TAG
    (stack / "env").mkdir(parents=True)
    (stack / "compose.yml").write_text(compose(STAGING_POSTGRES))
    (host.state / "staging" / "release").write_text(STAGING_TAG + "\n")
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
        "pull",
        "create",
        "cp",
        "rm",
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
    assert args[-6:] == [FETCH_IMAGE, "python", "manage.py", "restore_drill", "fetch", "/drill"]
    assert str(host.root / "etc" / "prod-drill.env") in fetch["env_files"]
    assert set(env_file(fetch, skip="prod-drill.env")) == THROWAWAY_KEYS


def test_the_check_image_is_the_release_that_took_the_backup(host: Host) -> None:
    result = host.run()

    assert result.docker("pull") == [["pull", "--quiet", CHECK_IMAGE]]
    assert result.docker("create") == [["create", "--name", COPIER, CHECK_IMAGE]]
    [copy] = result.docker("cp")
    assert copy[1] == f"{COPIER}:/app/deploy/compose.yml"
    assert Path(copy[2]).parent.parent == host.root / "tmp"
    # The temporary container goes as soon as the file is out, and again on exit.
    assert result.docker("rm")[-2:] == [
        ["rm", "-f", COPIER],
        ["rm", "-f", "wassal-drill-db", COPIER],
    ]


def test_the_backups_release_is_read_as_data_from_the_fetched_metadata(host: Host) -> None:
    other = "f" * 40
    line = PASS_LINE.replace(RELEASE, other)

    result = host.run(STUB_BACKUP_JSON=metadata(release=other), STUB_CHECK_OUTPUT=f"{line}\n")

    assert result.code == 0, result.stderr
    assert result.docker("pull") == [["pull", "--quiet", f"{REPO}:sha-{other}"]]
    assert result.run_of("check")["args"][-6] == f"{REPO}:sha-{other}"
    assert host.results.read_text() == line + "\n"


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
    assert args[-6:] == [CHECK_IMAGE, "python", "manage.py", "restore_drill", "check", "/drill"]
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


@pytest.mark.parametrize(
    "step", ["fetch", "pull", "create", "cp", "network", "volume", "database", "ready"]
)
def test_a_failed_step_still_cleans_up_and_pings_fail(host: Host, step: str) -> None:
    result = host.run(STUB_FAIL=step)

    assert result.code == 1
    assert result.steps()[-4:] == ["curl", "rm", "volume rm", "network rm"]
    assert result.docker("rm")[-1] == ["rm", "-f", "wassal-drill-db", COPIER]
    assert result.docker("volume", "rm")[-1] == ["volume", "rm", "wassal-drill-pgdata"]
    assert result.docker("network", "rm")[-1] == ["network", "rm", "wassal-drill"]
    assert result.ping_url == f"{PING}/fail"
    assert not host.drill_dir.exists()
    assert "check" not in result.steps()


@pytest.mark.parametrize(
    "release",
    [
        None,
        "",
        RELEASE[:-1],
        RELEASE + "0",
        RELEASE.upper(),
        f"sha-{RELEASE}",
        f"{RELEASE[:-1]}g",
        f"{RELEASE}\\n{RELEASE}",
        "../../etc",
    ],
)
def test_a_bad_backup_release_pings_fail_and_pulls_nothing(host: Host, release: str | None) -> None:
    result = host.run(STUB_BACKUP_JSON=metadata(release=release))

    assert result.code == 1
    assert result.ping_url == f"{PING}/fail"
    assert "release" in result.ping["body"]
    assert result.docker("pull") == []
    assert result.docker("create") == []
    assert result.steps()[-4:] == ["curl", "rm", "volume rm", "network rm"]
    assert not host.drill_dir.exists()


def test_a_second_release_field_is_refused(host: Host) -> None:
    text = metadata().replace('  "release"', f'  "release": "{"e" * 40}",\n  "release"', 1)

    result = host.run(STUB_BACKUP_JSON=text)

    assert result.code == 1
    assert result.docker("pull") == []


def test_a_compose_file_with_no_postgres_image_pings_fail(host: Host) -> None:
    result = host.run(STUB_COMPOSE="services:\n  api:\n    image: x\n")

    assert result.code == 1
    assert result.ping_url == f"{PING}/fail"
    assert "no postgres image" in result.ping["body"]
    assert "database" not in result.steps()
    assert result.docker("rm")[-1] == ["rm", "-f", "wassal-drill-db", COPIER]


def test_a_result_from_another_release_pings_fail(host: Host) -> None:
    line = PASS_LINE.replace(RELEASE, "e" * 40)

    result = host.run(STUB_CHECK_OUTPUT=f"{line}\n")

    assert result.code == 1
    assert result.ping_url == f"{PING}/fail"
    assert "not the backup's" in result.ping["body"]
    assert not host.results.exists()


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


# -- the staging host only -------------------------------------------------------------------------


@pytest.mark.parametrize(
    "text",
    [
        "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=staging\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=prod\nWG_ADDRESS=10.67.0.1\n",
        "WASSAL_ENV=dev\nWG_ADDRESS=10.67.0.1\n",
        "WASSAL_ENV=staging\n",
        "WG_ADDRESS=10.67.0.1\n",
        "WASSAL_ENV=staging\nWASSAL_ENV=prod\nWG_ADDRESS=10.67.0.1\n",
        "WASSAL_ENV=staging \nWG_ADDRESS=10.67.0.1\n",
        "WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\n\n",
        "# the staging host\nWASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\n",
        "export WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\n",
        "WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\nOTHER=1\n",
        'WASSAL_ENV="staging"\nWG_ADDRESS=10.67.0.1\n',
        "WASSAL_ENV=staging\r\nWG_ADDRESS=10.67.0.1\r\n",
        "WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\nWG_ADDRESS=10.67.0.1\n",
        "",
        None,
    ],
)
def test_the_drill_runs_on_the_staging_host_only(host: Host, text: str | None) -> None:
    path = host.root / "etc" / "host.env"
    if text is None:
        path.unlink()
    else:
        path.write_text(text)

    result = host.run()

    assert result.code == 2
    assert result.calls == []
    assert "host.env" in result.stderr or "staging host" in result.stderr


def test_host_env_is_read_as_data_never_sourced(host: Host) -> None:
    marker = host.root / "sourced"
    (host.root / "etc" / "host.env").write_text(
        f"WASSAL_ENV=staging$(touch {marker})\nWG_ADDRESS=10.67.0.1\ntouch {marker}\n"
    )

    result = host.run()

    assert result.code == 2
    assert not marker.exists()


@pytest.mark.parametrize("text", [None, "", "v1.2.3\n", "sha-123\n", f"{STAGING_TAG}x\n"])
def test_no_staging_release_pings_fail_and_starts_nothing(host: Host, text: str | None) -> None:
    path = host.state / "staging" / "release"
    if text is None:
        path.unlink()
    else:
        path.write_text(text)

    result = host.run()

    assert result.code == 1
    assert result.steps() == ["curl"]
    assert result.ping_url == f"{PING}/fail"
    assert "staging release" in result.ping["body"]


def test_the_ping_url_is_required(host: Host) -> None:
    result = host.run(HC_PING_DRILL_URL="")

    assert result.code == 2
    assert result.calls == []


@pytest.mark.parametrize("args", [("dev",), ("staging",), ("prod", "extra")])
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
