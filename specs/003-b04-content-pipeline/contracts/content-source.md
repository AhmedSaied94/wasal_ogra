# Contract: The `content/source` Layout, Import and Export (FR-015, FR-040)

One layout serves several purposes:

- **The repository's `content/source/`**: the exports of packs promoted to production;
- **The sample content**: `content/examples/sample/`;
- **The admin's zip import and export.**

Every file is one pack part, valid against that part's schema, so CI and the importer use the same
validator (research R9).

## Layout

```text
<root>/
├── pack.json                    # {"pack_id": "core", "schema_version": "1.0", "version": 12}
├── catalog.json                 # Catalog
├── daily_rewards.json           # array of DailyRewardDay (7)
├── tasks.json                   # array of TaskTemplate
├── lines/<line_id>.json         # Line (stations inside)
├── vehicles/<vehicle_id>.json   # Vehicle (seats inside)
├── trips/<line_id>/<trip_id>.json   # TripDefinition
├── chapters/<chapter_id>.json   # Chapter (scenes and panels inside)
├── rooms/<room_id>.json         # Room
├── items/<item_id>.json         # Item (variants inside)
├── family_requests/<request_id>.json
└── speech/<speech_key>.json     # SpeechPool
```

- **`pack.json`** holds only `pack_id`, `schema_version` and the `version` the export came from.
  An export of current content that was never published has `"version": 0`. Its presence in the
  repository's `content/source/` switches on the breaking-change check (research R3).
- **File names** must equal the identifier inside the file. A mismatch is an import error.
- **Assembling** the parts, sorted by identifier within each array, plus `pack.json`'s `pack_id`
  and `schema_version` and a version, gives exactly the `Pack` that a build of the same content
  produces. That is what lets CI validate `content/source` as a whole pack.
- **Derived fields are written** by export and **checked, not trusted**, by import:
  - trip `seats` must match the vehicle;
  - trip `rev`: import keeps it, a build recomputes it (FR-023).

## Export format

Every file is written so that diffs are small and reviewable, and identical across machines
(FR-015):

- sorted keys and 2-space indentation;
- UTF-8 without a BOM, `ensure_ascii` off;
- `\n` line endings and a trailing newline.

Authoring-only data is never exported: speech-line reviews, author notes and the change history.

## Import rules

| Rule | Limit or behavior |
| --- | --- |
| Upload | One `.zip`, at most 4 MiB. The admin hostname's edge limit is 8 MiB, leaving room for the multipart framing (research R9). |
| Entries | At most 2,000, and at most 8 MiB uncompressed in total, which is about 4× the MVP content and keeps parsing within the staging admin's 256 MB. Each entry at most 1 MiB. |
| Paths | Only the paths of the layout above. Absolute paths, `..`, backslashes, symlinks and directories outside the layout are refused. |
| Parsing | Strict loader: integers only, UTF-8, no duplicate keys (research R2) |
| Validation | Every file against its schema, then the assembled pack through stages 1–3 (contracts/content-schemas.md). Review state is not part of import. |
| Apply | In one transaction: create or update by identifier. Entities absent from the zip are left alone, except that nested lists replace the old ones: a trip's passengers, stations and events, a line's stations, a vehicle's seats, an item's variants, a pool's lines, a chapter's scenes. |
| Permanence | A nested replacement that would rename or drop a permanent identifier (FR-016) refuses the whole import |
| Speech lines | Imported lines whose text matches the stored text keep their review. New or changed lines are unreviewed (FR-017). |
| Result | All or nothing. The report lists each file, path and problem (US2-3), and is kept in the admin's message and in the change history. |
| Who | `content.import_content`, on `CONTENT_ROLE=source` only |

## Export

| Export | Who | Content |
| --- | --- | --- |
| Current content | Authors | Everything authored now, with `pack.json` `version: 0` |
| A published pack | Authors and publishers | Exactly that pack's parts, read back from its stored file, with its version |

A publisher exports each promoted pack and commits it to `content/source/` through a pull request
(FR-040). The quickstart has the steps.

## Management commands (same rules as the admin)

| Command | Use |
| --- | --- |
| `manage.py content_import <dir-or-zip> --actor <staff>` | The import above, run as `actor` |
| `manage.py content_export <dir> [--version N] --actor <staff>` | The export above. The current content needs `content.export_content` and `CONTENT_ROLE=source`. A published pack (`--version`) needs any active staff member. |

contracts/admin.md "Management commands" lists every command with its checks.

`wassal-content validate-source <dir>` (in `tools/content_kit`) validates a layout without Django,
and CI runs it on `content/source/` and `content/examples/sample/`.
