"""The host backup script and its units (FR-039, contracts/operations.md "Backup job").

`bin/backup` runs under bash with stub `docker` and `flock` first on `PATH`. The stubs log every
call with the environment compose would interpolate. Backups run on the prod host only, the one
whose `host.env` says `WASSAL_ENV=prod` (contracts/operations.md "Host identity").
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

BASH = shutil.which("bash") or "/bin/bash"
HOST = Path(__file__).resolve().parent.parent
BACKUP = HOST / "bin" / "backup"
TAG = "v1.2.3"
HOST_ENV = {
    "prod": "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\n",
    "staging": "WASSAL_ENV=staging\nWG_ADDRESS=10.67.0.1\n",
}

STUB = """
import json, os, sys
from pathlib import Path

name = Path(sys.argv[0]).name
state = Path(os.environ["STUB_DIR"])
seen = {key: os.environ.get(key) for key in ("RELEASE_TAG", "BACKUP_ENV_FILE", "BACKUP_STATE_DIR")}
with open(state / "calls.jsonl", "a") as log:
    log.write(json.dumps({"cmd": name, "args": sys.argv[1:], "env": seen}) + "\\n")
if name == "flock":
    sys.exit(1 if os.environ.get("STUB_FLOCK_FAIL") else 0)
sys.exit(int(os.environ.get("STUB_DOCKER_EXIT", "0")))
"""


@dataclass
class Host:
    root: Path

    @property
    def state(self) -> Path:
        return self.root / "state"

    @property
    def etc(self) -> Path:
        return self.root / "etc"

    @property
    def stubs(self) -> Path:
        return self.root / "stubs"

    def serve(self, env: str, tag: str) -> Path:
        stack = self.state / env / "deploy" / tag
        (stack / "env").mkdir(parents=True)
        (stack / "compose.yml").write_text("services: {}\n")
        (stack / "env" / f"{env}.env").write_text("API_PORT=8100\n")
        (self.state / env / "release").write_text(tag)
        return stack

    def run(self, *args: str, **stub_env: str) -> tuple[int, str, list[dict[str, Any]]]:
        env = {
            "PATH": f"{self.stubs}:{os.environ['PATH']}",
            "STUB_DIR": str(self.stubs),
            "WASSAL_STATE_DIR": str(self.state),
            "WASSAL_ETC": str(self.etc),
            "WASSAL_LOCK_DIR": str(self.root),
            "WASSAL_APP_UID": str(os.getuid()),
            "WASSAL_APP_GID": str(os.getgid()),
            **stub_env,
        }
        result = subprocess.run(  # noqa: S603 - fixed script and arguments
            [BASH, str(BACKUP), *args],
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
        log = self.stubs / "calls.jsonl"
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        log.unlink(missing_ok=True)
        return result.returncode, result.stderr, calls


@pytest.fixture
def host(tmp_path: Path) -> Host:
    host = Host(tmp_path)
    host.stubs.mkdir()
    for name in ("docker", "flock"):
        stub = host.stubs / name
        stub.write_text(f"#!{sys.executable}\n{STUB}")
        stub.chmod(0o755)
    host.etc.mkdir()
    (host.etc / "host.env").write_text(HOST_ENV["prod"])
    (host.etc / "prod-backup.env").write_text("B2_REGION=eu-central-003\n")
    return host


def test_it_runs_backup_db_in_the_serving_release(host: Host) -> None:
    stack = host.serve("prod", TAG)

    code, stderr, calls = host.run("prod")

    assert code == 0, stderr
    [lock, compose] = calls
    assert lock["cmd"] == "flock"
    assert compose["args"] == [
        "compose",
        "-p",
        "wassal-prod",
        "-f",
        str(stack / "compose.yml"),
        "--env-file",
        str(stack / "env" / "prod.env"),
        "--profile",
        "ops",
        "run",
        "--rm",
        "--no-deps",
        "-T",
        "backup",
    ]
    assert compose["env"] == {
        "RELEASE_TAG": TAG,
        "BACKUP_ENV_FILE": str(host.etc / "prod-backup.env"),
        "BACKUP_STATE_DIR": str(host.state / "prod" / "backup"),
    }


def test_the_state_directory_is_private_to_the_container_user(host: Host) -> None:
    host.serve("prod", TAG)

    host.run("prod")

    backup_dir = host.state / "prod" / "backup"
    assert stat.S_IMODE(backup_dir.stat().st_mode) == 0o750
    assert backup_dir.stat().st_uid == os.getuid()
    # The stack definitions next to it stay out of the container's reach.
    assert stat.S_IMODE((host.state / "prod").stat().st_mode) & 0o022 == 0


def test_a_failed_backup_exits_1(host: Host) -> None:
    host.serve("prod", TAG)

    code, stderr, _ = host.run("prod", STUB_DOCKER_EXIT="1")

    assert code == 1
    assert "backup_db failed (exit 1)" in stderr


def test_a_held_deploy_lock_exits_3(host: Host) -> None:
    host.serve("prod", TAG)

    code, _, calls = host.run("prod", STUB_FLOCK_FAIL="1")

    assert code == 3
    assert [call["cmd"] for call in calls] == ["flock"]


@pytest.mark.parametrize("args", [(), ("dev",), ("prod", "extra"), ("../prod",)])
def test_bad_arguments_exit_2(host: Host, args: tuple[str, ...]) -> None:
    host.serve("prod", TAG)

    code, _, calls = host.run(*args)

    assert code == 2
    assert calls == []


def test_nothing_runs_before_a_release_serves(host: Host) -> None:
    code, stderr, calls = host.run("prod")

    assert code == 2
    assert "no release serves prod yet" in stderr
    assert calls == []


def test_a_tampered_release_file_is_refused(host: Host) -> None:
    host.serve("prod", TAG)
    (host.state / "prod" / "release").write_text("../../etc")

    code, _, calls = host.run("prod")

    assert code == 2
    assert calls == []


def test_the_backup_env_file_is_required(host: Host) -> None:
    host.serve("prod", TAG)
    (host.etc / "prod-backup.env").unlink()

    code, stderr, calls = host.run("prod")

    assert code == 2
    assert "prod-backup.env is missing" in stderr
    assert calls == []


# -- host identity ---------------------------------------------------------------------------------


@pytest.mark.parametrize("env", ["prod", "staging"])
def test_the_staging_host_never_backs_up(host: Host, env: str) -> None:
    # Even with a release and a backup env file left from the one-host design.
    (host.etc / "host.env").write_text(HOST_ENV["staging"])
    (host.etc / "staging-backup.env").write_text("B2_REGION=eu-central-003\n")
    host.serve(env, TAG)

    code, stderr, calls = host.run(env)

    assert code == 2
    assert "the prod host only" in stderr
    assert calls == []
    assert not (host.state / env / "backup").exists()


def test_the_prod_host_backs_up_prod_only(host: Host) -> None:
    (host.etc / "staging-backup.env").write_text("B2_REGION=eu-central-003\n")
    host.serve("staging", "sha-" + "a" * 40)

    code, stderr, calls = host.run("staging")

    assert code == 2
    assert "this host serves prod" in stderr
    assert calls == []
    assert not (host.state / "staging" / "backup").exists()


def test_a_missing_host_env_exits_2(host: Host) -> None:
    host.serve("prod", TAG)
    (host.etc / "host.env").unlink()

    code, stderr, calls = host.run("prod")

    assert code == 2
    assert "host.env is missing" in stderr
    assert calls == []


@pytest.mark.parametrize(
    "contents",
    [
        "",
        "WASSAL_ENV=prod\n",  # no WG_ADDRESS
        "WG_ADDRESS=10.66.0.1\n",  # no WASSAL_ENV
        "WASSAL_ENV=dev\nWG_ADDRESS=10.66.0.1\n",
        "WASSAL_ENV=prod\nWG_ADDRESS=10.67.0.1\n",  # staging's address on prod
        "WASSAL_ENV=prod\nWASSAL_ENV=staging\nWG_ADDRESS=10.66.0.1\n",
        'WASSAL_ENV="prod"\nWG_ADDRESS=10.66.0.1\n',
        "WASSAL_ENV=prod\nWG_ADDRESS=10.66.0.1\nPATH=/tmp\n",  # only the two lines belong
        "WASSAL_ENV=prod\r\nWG_ADDRESS=10.66.0.1\r\n",
    ],
)
def test_a_malformed_host_env_exits_2(host: Host, contents: str) -> None:
    host.serve("prod", TAG)
    (host.etc / "host.env").write_text(contents)

    code, stderr, calls = host.run("prod")

    assert code == 2
    assert "host.env" in stderr
    assert calls == []


def test_host_env_is_read_as_data(host: Host) -> None:
    host.serve("prod", TAG)
    marker = host.root / "sourced"
    (host.etc / "host.env").write_text(f"{HOST_ENV['prod']}touch {marker}\n")

    host.run("prod")

    assert not marker.exists()


# -- units -----------------------------------------------------------------------------------------


def unit(name: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in (HOST / "systemd" / name).read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key] = value
    return values


def test_the_timer_runs_nightly_at_three_cairo_time() -> None:
    timer = unit("wassal-backup@.timer")

    assert timer["OnCalendar"] == "*-*-* 03:00:00 Africa/Cairo"
    assert timer["Persistent"] == "true"
    assert timer["WantedBy"] == "timers.target"


def test_the_service_runs_the_script_with_a_memory_cap() -> None:
    service = unit("wassal-backup@.service")

    assert service["ExecStart"] == "/opt/wassal/bin/backup %i"
    assert service["MemoryMax"] == "1G"
    assert service["Type"] == "oneshot"
    assert service["ConditionPathExists"] == "/etc/wassal/%i-backup.env"
