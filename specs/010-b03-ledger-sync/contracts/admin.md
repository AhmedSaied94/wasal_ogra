# Contract: The Economy in the Admin

All pages are in B01's staff admin: separate hostname, reachable only over its VM's WireGuard,
2FA on every view, lockout after repeated failures. Staff accounts are made with `create_staff
<name> [--group …]`. Nothing here shows a token, an install id, a provider subject or a payload.

## Groups and permissions

| Group | Origin | Permissions added by this feature |
| --- | --- | --- |
| `player_support` | B02 | view wallet, ledger entry, processed op, inventory, grant record, ownership, trip progress, story state; view flag; change flag (review) |
| `economy_ops` | new, migration `economy/0002_groups` | everything `player_support` adds here, plus view player (not change: the tester flag stays with support), view wallet adjustment, the custom permission `economy.adjust_wallet`, and view/add/change/delete on the name filter |
| `content_author` | B04 | none |

A superuser has all of them. The adjustment and the name filter are the only writes to money or
text rules, so they are not in `player_support`.

## On the player page (`PlayerAdmin`, B02)

Read-only blocks, shown to anyone who can view a player and the model:

- **Wallet:** JENEHAT, BONAT, fuel (now, recounted), window end, `state_version`, last active,
  comeback return.
- **Recent ledger:** the last 50 entries (time, currency, delta, balance after, reason, source,
  reference), newest first, with a link to the full list filtered to the player.
- **Inventory, ownership, trip progress** (best stars per trip), **story** (chapters and scenes
  seen), **grants**.
- **Open flags:** kind, date, details, with a link to review.
- **Recent operations:** the last 50 processed operations (time, type, status, reason). Never the
  payload.
- **Adjustments:** the last 50 (time, currency, delta, reason, staff user). Shown to anyone who can
  view the player. The "Adjust balance…" link is in the page's tools, only with
  `economy.adjust_wallet`.

## Flags (`PlayerFlagAdmin`)

- List: player, kind, date, count, reviewed (yes/no), reviewer. Filters: kind, reviewed, date.
  Default filter: not reviewed. Search by player id.
- Action "Mark reviewed": a form with a required resolution (up to 200 characters). It records the
  reviewer (the staff user) and the time. A reviewed flag cannot be changed again.
- Flags cannot be added or deleted from the admin.
- The flag list is the queue leagues (phase 3) will read to exclude players.

## Adjusting a balance

Admin action "Adjust balance…" on the player page, shown only with `economy.adjust_wallet`.

- Form: currency (JENEHAT or BONAT), a signed non-zero integer amount, a required reason (up to 200
  characters), and a confirmation checkbox. The page shows the balance before and the balance the
  adjustment would give, and refuses a result below 0.
- It calls `adjustments.adjust(...)`: locks the wallet, writes one `LedgerEntry` with reason
  `admin_adjustment`, source `admin`, ref `adjustment` and the new record's id, and one `WalletAdjustment` (actor,
  player, currency, delta, reason, ledger entry, time). Both in one transaction. It bumps
  `state_version` so a stale phone is told to refresh.
- `WalletAdjustment` is append-only and visible to anyone who can view the player. It is the audit
  log of backend §13 for adjustments. For flag reviews the audit record is the flag's reviewer, time
  and resolution (see Flags). Neither is edited or deleted in the admin.
- There is no way to move value between currencies or players. Two adjustments are two records.

## The name filter (`NameFilterEntryAdmin`)

- List: term, normalized form, added by, date. Search by term. Add, edit, delete with the
  `economy_ops` permissions. Django's admin log records each change (who, what, when).
- The entry shows its normalized form once saved (the list shows it too, and the save message
  names it), from the same function the check uses. The admin runs no script (as B04's pages), so
  it is not shown while typing. A term with no letters left after normalization, or one whose
  normalized form another entry has, is refused by the form.
- A new entry applies to the next `settings_update`. Names already chosen are not re-checked.
- The migration inserts a seed list. The owner reviews it after the first deploy.

## Not in the admin

Editing balances directly, deleting ledger rows, editing a processed operation, granting items,
raising or clearing a flag outside the review action. A mistake is corrected by an adjustment, and
the record of it stays.

## Tests

`test_admin_economy.py` covers: each page's permission matrix (support sees, ops adjusts, a staff
user with neither is refused), the adjustment (ledger entry, record, version, refusal below 0),
the review action, that no page contains a payload or token, and the name filter's normalization.
