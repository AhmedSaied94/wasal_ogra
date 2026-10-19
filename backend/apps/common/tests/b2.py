"""A fake B2 for the backup and drill tests: moto's in-process S3, at the boto3 boundary only."""

from __future__ import annotations

import os
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from unittest import mock

import boto3
from moto import mock_aws

from apps.common.services.backups import BackupConfig

ENDPOINT = "https://s3.eu-central-003.backblazeb2.com"
REGION = "eu-central-003"
DAILY = "wassal-test-daily"
WEEKLY = "wassal-test-weekly"
PING = "https://hc.example.test/backup-uuid"
RELEASE = "a" * 40
SUNDAY = datetime(2026, 10, 18, 1, 0, 0, tzinfo=UTC)
MONDAY = datetime(2026, 10, 19, 1, 0, 0, tzinfo=UTC)
TUESDAY = datetime(2026, 10, 20, 1, 0, 0, tzinfo=UTC)


@contextmanager
def fake_b2() -> Iterator[Any]:
    """Both buckets, empty. Yields a client for the test's own reads and writes."""
    with mock.patch.dict(os.environ, {"MOTO_S3_CUSTOM_ENDPOINTS": ENDPOINT}), mock_aws():
        client = boto3.client(
            "s3",
            endpoint_url=ENDPOINT,
            region_name=REGION,
            aws_access_key_id="test",
            aws_secret_access_key="test",
        )
        for bucket in (DAILY, WEEKLY):
            client.create_bucket(
                Bucket=bucket, CreateBucketConfiguration={"LocationConstraint": REGION}
            )
        yield client


def backup_config(state_dir: Path) -> BackupConfig:
    return BackupConfig(
        environment="prod",
        release=RELEASE,
        s3_endpoint=ENDPOINT,
        s3_region=REGION,
        daily_bucket=DAILY,
        weekly_bucket=WEEKLY,
        key_id="test",
        app_key="test",
        prefix="prod",
        weekly_weekday=6,
        ping_url=PING,
        state_file=state_dir / "last-backup.json",
    )


def keys(client: Any, bucket: str) -> list[str]:
    listing = client.list_objects_v2(Bucket=bucket, Prefix="prod/")
    return sorted(item["Key"] for item in listing.get("Contents", []))


def read(client: Any, bucket: str, key: str) -> bytes:
    return client.get_object(Bucket=bucket, Key=key)["Body"].read()  # type: ignore[no-any-return]
