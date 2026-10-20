"""The worker's startup check of `CONTENT_PACKS_DIR` (contracts/environment.md)."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from celery.signals import worker_init
from pytest_django import Settings

from apps.content.checks import check_packs_dir_on_worker_start, packs_dir_problem


def test_a_writable_directory_passes(tmp_path: Path) -> None:
    assert packs_dir_problem(tmp_path) is None
    assert list(tmp_path.iterdir()) == []


def test_a_missing_directory_fails(tmp_path: Path) -> None:
    assert packs_dir_problem(tmp_path / "missing") == (
        "CONTENT_PACKS_DIR doesn't exist or isn't a directory"
    )


def test_a_file_fails(tmp_path: Path) -> None:
    (tmp_path / "file").write_text("")

    assert packs_dir_problem(tmp_path / "file") is not None


@pytest.mark.skipif(os.geteuid() == 0, reason="root writes to read-only directories")
def test_a_read_only_directory_fails(tmp_path: Path) -> None:
    tmp_path.chmod(0o555)
    try:
        assert packs_dir_problem(tmp_path) == "CONTENT_PACKS_DIR isn't writable by the worker"
    finally:
        tmp_path.chmod(0o755)


def test_the_check_runs_when_a_worker_starts() -> None:
    assert any(key[0] == "content.packs_dir" for key, _ in worker_init.receivers)


def test_the_worker_stops_on_a_problem(tmp_path: Path, settings: Settings) -> None:
    settings.CONTENT_PACKS_DIR = tmp_path / "missing"

    # Celery logs and swallows a receiver's Exception, but not SystemExit.
    with pytest.raises(SystemExit, match="CONTENT_PACKS_DIR doesn't exist"):
        check_packs_dir_on_worker_start()


def test_the_worker_starts_with_a_writable_directory(tmp_path: Path, settings: Settings) -> None:
    settings.CONTENT_PACKS_DIR = tmp_path

    check_packs_dir_on_worker_start()


def test_dev_creates_the_directory(tmp_path: Path, settings: Settings) -> None:
    settings.WASSAL_ENV = "dev"
    settings.CONTENT_PACKS_DIR = tmp_path / "var" / "packs"

    check_packs_dir_on_worker_start()

    assert (tmp_path / "var" / "packs").is_dir()


@pytest.mark.skipif(os.geteuid() == 0, reason="root writes to read-only directories")
def test_dev_stops_when_it_cant_create_the_directory(tmp_path: Path, settings: Settings) -> None:
    settings.WASSAL_ENV = "dev"
    settings.CONTENT_PACKS_DIR = tmp_path / "var" / "packs"
    tmp_path.chmod(0o555)
    try:
        # A PermissionError would be swallowed by Celery, so it must become SystemExit too.
        with pytest.raises(SystemExit, match="CONTENT_PACKS_DIR doesn't exist"):
            check_packs_dir_on_worker_start()
    finally:
        tmp_path.chmod(0o755)
