"""The name filter's seed list (B03 research R10, data-model.md "Migrations").

The terms are data, in `apps/accounts/data/name_filter_seed.json`, normalized here with the same
function the name check uses. The owner reviews them in the admin after the first deploy.
"""

import json
from pathlib import Path
from typing import Any

from django.db import migrations

SEED = Path(__file__).resolve().parent.parent / "data" / "name_filter_seed.json"


def seed(apps: Any, schema_editor: Any) -> None:
    from apps.accounts.services.names import normalize

    entry = apps.get_model("accounts", "NameFilterEntry")
    for term in json.loads(SEED.read_text(encoding="utf-8"))["terms"]:
        normalized = normalize(term)[:40]
        if normalized:
            entry.objects.get_or_create(normalized=normalized, defaults={"term": term[:40]})


def unseed(apps: Any, schema_editor: Any) -> None:
    apps.get_model("accounts", "NameFilterEntry").objects.filter(added_by=None).delete()


class Migration(migrations.Migration):
    dependencies = [("accounts", "0005_player_settings_name_filter")]

    operations = [migrations.RunPython(seed, unseed)]
