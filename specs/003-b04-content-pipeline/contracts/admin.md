# Contract: The Content Admin (FR-012–FR-019, FR-038)

Everything here runs on B01's admin role: its own hostname, private network only, staff accounts
with TOTP and lockout. All pages are standard Django admin, with no inline JavaScript, so B01's
admin CSP is unchanged.

## Roles

| Group | Permissions | Can |
| --- | --- | --- |
| `content_author` | add/change/delete on every authoring model, `content.import_content`, `content.export_content`, `content.build_pack`, `content.review_speech` | edit, import, export current content, build, review lines |
| `content_publisher` | `content.publish_pack`, `content.rollback_pack`, `content.promote_pack`, `content.change_min_client_version` | publish, roll back, promote, change the minimum app version |
| any staff | view on every content model and on `ContentPack` and `ContentAuditRecord` | read, and export published packs |

- **Who assigns roles.** The operator gives the groups with `manage.py create_staff <name> --group
  content_author` (B01's command gains `--group`), or in the admin's user page.
- **Groups combine:** the owner holds both.
- **Superusers** get no audit-log write access (data-model).
- **Who counts as an actor.** Every check needs an active staff account with the permission. An
  inactive or non-staff account is refused like one without the permission.

## What each environment offers

`CONTENT_ROLE` decides (research R9):

| Page or action | `source` (dev, test, staging) | `target` (production) |
| --- | --- | --- |
| Authoring models | add, change, delete (with permission) | read-only for everyone |
| Import zip | yes | no |
| Export current content | yes (`export_content`) | no (nothing is authored there) |
| Export a published pack | yes | yes |
| Build a draft pack | yes | no |
| Publish, roll back | yes | no |
| Promote | no | yes |
| Change minimum app version | yes | yes |
| Mark speech lines reviewed | yes | no |

The settings check refuses `CONTENT_ROLE=source` with `WASSAL_ENV=prod`, and `target` with any
other environment.

## Management commands

Commands call the same services as the admin, so they make the same checks (FR-019). Every command
that acts for a person needs `--actor <username>`. Without it, the command stops before doing
anything.

| Command | Needs | Refused on |
| --- | --- | --- |
| `content_import <dir-or-zip> --actor <staff>` | `import_content` | `target` |
| `content_export <dir> --actor <staff>` (current content) | `export_content` | `target` |
| `content_export <dir> --version N --actor <staff>` (a published pack) | any active staff member | — |
| `content_build --actor <staff> [--dry-run] [--version N]` | `build_pack`, also with `--dry-run` | `target` |
| `content_files sync [--verify]` | no actor | — |

`content_files sync` is the one command without an actor. It changes no content, makes nothing
current, and only writes files that are already published, plus production's floor file
(contracts/pack-delivery.md).

## Authoring pages

| Page | Inlines | Notes |
| --- | --- | --- |
| Line | Stations | Ordered by `order`. Unlock fields are shown and validated by kind. |
| Vehicle | Seats | — |
| Trip | Stations, passengers, events | The tray is eight number fields, one per denomination. `seed` is pre-filled. `rev` is read-only. The changelist filters by line and kind, and searches by `trip_id`. |
| Chapter | Scenes (link to the scene page) | Goal fields are validated by `goal_kind` |
| Scene | Scene lines | `panel_art` is a comma-separated slug list, 3–5 items |
| Room, Item | Variants (on Item) | — |
| Family request | — | `variant` is limited to the chosen item's variants |
| Speech pool | Lines | Bulk action on lines: "Mark reviewed" (`content.review_speech`). The review columns are read-only, and the changelist filters by "has unreviewed lines". |
| Catalog price | — | `currency` is chosen from `sku_kind` and validated |
| Daily reward day, Task template | — | — |

- **Arabic text fields** are inputs or textareas with `dir="rtl" lang="ar"` (FR-014).
- **Saving.** Form errors appear next to their field and nothing is saved (FR-013).
- **Permanence.** A permanent identifier's field is read-only. A delete that would remove one is
  refused with a message naming the pack version that published it (FR-016).

## Pack pages

**ContentPack changelist** shows version, status, build state, origin, `sha256` (shortened), size,
minimum app version and dates, plus:

| Action | Permission and role | Effect |
| --- | --- | --- |
| "Build a new pack" (changelist button) | `build_pack`, `source` | Queues a build (R10). The page shows `queued`, then `running`, then the result. |
| "Publish" (on a validated pack) | `publish_pack`, `source` | Asks for confirmation, then queues the publish (contracts/pack-delivery.md) |
| "Roll back to this" (on a published or retired pack) | `rollback_pack`, `source` | Builds that pack's content as a new version with `rollback_of` set. The publisher then publishes it like any other pack (FR-028). |
| "Promote from staging" (changelist button) | `promote_pack`, `target` | A form with one field, the promotion code. Queues the promotion. |
| "Change minimum app version" (on a published or retired pack) | `change_min_client_version`, both roles | A form with the new value. It is refused below the floor for the pack's schema major (FR-032), and writes an audit record. |
| "Download pack file", "Export content" | any staff | Streams the stored file, or the `content/source` zip of that pack |

**The pack detail page** shows the validation report grouped by stage. Errors come first, each
with its code, entity, identifier, path and message, and a link to the authoring object when it
exists. On `source` the page also shows the **promotion code** of published packs (R6).

**ContentAuditRecord changelist** is read-only for everyone, with filters for action, outcome,
actor and version.

## Validation report (`ContentPack.validation_report`)

```json
{
  "snapshot_at": "2026-11-02T10:00:00Z",
  "schema_version": "1.0",
  "stages": {
    "schema":        {"result": "passed"},
    "references":    {"result": "failed"},
    "content_rules": {"result": "passed"},
    "review":        {"result": "passed"},
    "solver":        {"result": "not_available"},
    "size":          {"result": "passed", "bytes": 412233}
  },
  "findings": [
    {"stage": "references", "code": "V-T4", "severity": "error", "entity": "trip",
     "id": "line_gamaa.12", "path": "$.passengers[2].dest_station_id",
     "message": "dest_station_id 'souq' is not a station of this trip"}
  ]
}
```

- **Stage results** are `passed`, `warning`, `failed` or `not_available`.
- **The pack becomes `validated`** only when every result is `passed` or `warning` (FR-022). The
  solver is the exception, which must be `passed` before a publish (contracts/pack-delivery.md).
- **Messages** are English, for staff. They never contain secrets or personal data. Identifiers and
  paths are content data.

## Audit records written (FR-038)

These five actions write an audit record. Each one is written for both a successful and a failed
attempt:

- publish;
- promote;
- rollback (when its build is queued and when it is published);
- minimum app version change.

Each record holds the fields in data-model `ContentAuditRecord`. Builds themselves are not audited:
the pack record keeps who built it and when, along with its report.
