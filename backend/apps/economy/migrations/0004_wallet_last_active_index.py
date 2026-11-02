"""An index on `Wallet.last_active_at`: the version page counts the players active in 7 days
(B10 research R10, US2). Expand-only and concurrent, so a live table isn't locked while the
previous release still serves."""

from django.contrib.postgres.operations import AddIndexConcurrently
from django.db import migrations, models


class Migration(migrations.Migration):
    atomic = False

    dependencies = [("economy", "0003_prune_schedule")]

    operations = [
        AddIndexConcurrently(
            model_name="wallet",
            index=models.Index(fields=["last_active_at"], name="wallet_last_active_idx"),
        ),
    ]
