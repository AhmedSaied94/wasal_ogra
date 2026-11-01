# Contract: Admin, Command and Permissions

## Group `live_ops`

Created by migration (the pattern of `economy/0002_groups`). Only it and superusers have:

| Model | Permissions |
| --- | --- |
| `LiveSetting` | view, change |
| `StoreProduct` | view, add, change |
| `Offer` | view, add, change |
| `LiveopsChange` | view |
| `RemoteConfigCheck` | view |
| custom | `liveops.switch_maintenance` |

No delete permission exists in practice for any of them (products and offers are deactivated or
ended, never deleted). `create_staff <name> --group live_ops` adds a member. B01's TOTP login and
WireGuard apply as for every staff page.

## Pages

- **Live settings** (`LiveSetting` changelist): key, value, default, `applied_by`, meaning, the drift
  value when the latest check saw one, last change (who, when). Filters: `applied_by`, changed from
  default, drifted. The change form shows the registry's range or choices, a note field, and the
  history below. A "Reset to default" action writes a `reset` change. Saves go through
  `liveops.services.settings_admin.change(key, value, actor, note, source)`.
- **App versions** (a custom page linked from the version settings): per platform, active players
  (last 7 days) per `MAJOR.MINOR.PATCH`, and "unknown"; a form with a proposed minimum shows how many
  and what share it would block, then a confirm step saves it (FR-032).
- **Maintenance** (a custom page, `switch_maintenance` permission): state, end time, a form to turn it
  on with an optional end time and a note, and off. Saves through
  `liveops.services.maintenance.switch(...)`.
- **Store products** and **Offers**: list and form; the form validates through the service (kind and
  grants coherence, one best value, known product ids, the rules of contracts/offers.md). History
  below each.
- **Remote Config checks**: read-only list of runs, newest first.
- **Change history** (`LiveopsChange`): read-only list, filter by target, key, actor, source.

## Command `maintenance`

```text
uv run manage.py maintenance status
uv run manage.py maintenance on --actor <staff> [--until 2026-11-03T15:30Z] [--note "…"]
uv run manage.py maintenance off --actor <staff> [--note "…"]
```

- `--actor` must name an active staff user with `liveops.switch_maintenance`; otherwise exit 2 with
  the reason, and nothing changes.
- `--until` is ISO-8601 with a zone and must be in the future.
- Writes a `command` change. Prints the new state and "applies within 60 s".
- On a host: `sudo docker compose -p wassal-<env> exec api uv run manage.py maintenance …`
  (`docs/runbooks/deploy-and-rollback.md`, "Maintenance window").
