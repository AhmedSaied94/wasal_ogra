# Contract: The Driver's Name

The Name card, the rules the phone checks, the suggestions, the operation, a refusal and the re-ask.
Spec FR-011–FR-019, Clarifications Q3; research R7, R8.

## `NameRules` (pure, `lib/features/onboarding/domain/name_rules.dart`)

```text
NameCheck check(String raw)   →  ok(normalized) | empty | tooShort | onlyDigits | badCharacters
```

1. Normalize: trim, and collapse every run of whitespace to one space. No NFKC on the phone (Dart's
   core libraries have none); the server normalizes before its own check.
2. `empty` when nothing is left; `badCharacters` for any control (Cc), format (Cf: bidi marks,
   zero-width joiners and spaces) or private-use character; `onlyDigits` when every character is a
   Western or Arabic-Indic digit (spaces aside); `tooShort` under 2 characters (grapheme clusters).
3. The field's `maxLength` is 16 (`AppTextField`), applied to the raw text, so a paste is cut at 16
   before the check.

The server's filter list (B03 `NameFilterEntry`) is not on the phone. Its other rules are B03 R10's,
with 20 as its maximum.

## Suggestions

- `namePool` in `app_ar.arb`: one string, names separated by «،». It is parsed once and trimmed, and
  empty parts are dropped.
- Starting list (24): حمادة، سيد، عبده، شريف، ميدو، حسن، كريم، مصطفى، تامر، وليد، عادل، سامح، رضا،
  أشرف، هاني، محمود، فتحي، جمعة، صلاح، عصام، حمدي، ناصر، ربيع، شعبان. The owner approves it.
- The first suggestion is random (seeded from the trusted clock, so tests inject the seed). The dice
  picks again, never the name showing.
- Checks:
  - Dart: every name passes `NameRules`, and there are at least 20 (`name_pool_test.dart`);
  - backend: `apps/accounts/tests/test_name_pool.py` reads `apps/mobile/lib/l10n/app_ar.arb` and runs
    each name through the `settings_update` name validator with the seeded filter: 0 refusals.

## The Name card (`/onboarding/name`, `lib/features/onboarding/presentation/name_screen.dart`)

Built to the `Name` artboard with 008.5's components:

| Block | Component | Notes |
| --- | --- | --- |
| Background | `ground` + two `primary.soft` circles | as drawn |
| Card | `AppCard` (r `scene`, lip `card.big`) | centred, moves up with the keyboard (`MediaQuery.viewInsets`) so it stays fully visible |
| Avatar | `CharacterAvatar('usta')` in a 112 `sun` circle | overlaps the card top by 56 |
| Title, subtitle, label | `nameTitle`, `nameSubtitle`, `nameFieldLabel` | |
| Field | `AppTextField(maxLength: 16, semanticLabel: nameFieldLabel)` | RTL, `TextInputAction.done` |
| Dice | `IconCircleButton`-sized 54×54 `sun.soft` with `dice.svg` | semantics `nameSuggestAnother` «اقترح اسم تاني»; 150 ms text swap |
| Helper | `nameHelper` | |
| CTA | `AppButton.primary(size: l)` 318×60 «تمام» | disabled (45%, no lip) unless `check` is `ok` |

- «تمام» or the keyboard's done key, when `ok`:
  1. `economy.setDisplayName(txnId, normalized)`;
  2. `context.go('/trip/<tutorialTrips[0]>')` (the redirects may put a scene or the lesson first:
     never, in practice, for trip 1).
- Back does nothing (`PopScope(canPop: false)`).
- Offline and online behave the same. Nothing waits for the server.

## The operation

- `Economy.setDisplayName(TxnId, String name)` → `OpApplied | OpRefused(invalidName) | OpWriteFailed`.
  - It records `settings_update` with payload `{"display_name": name}`.
  - Apply sets `EconomyState.displayName`.
- The sync sends it as is (M06's `opWire`), without `content_version`.
- The server accepts it (stored trimmed, NFKC), or rejects it with `validation_error`,
  `details.field = "display_name"`.

## The name shown

| Situation | Shown |
| --- | --- |
| A pending or accepted `settings_update` in the fold | its name (the projection's `displayName`) |
| None, and the server's state had a name | the server's (`displayName` from the base) |
| Neither | `driverNameDefault` «الأسطى» |

Exposed as `driverNameProvider` (String), for Home (M08) and anything else that shows the name. It
reads only the projection, never M06's `account.display_name` (data-model.md). Until M08 builds Home,
the playtest Home's header shows it (dev and staging).

## A refusal

- M06's `applyAnswer` marks the row `rejected` and refolds without it, so `displayName` falls back by
  itself (FR-017).
- `EconomyView.nameRefused`: the newest `settings_update` row (highest `seq`) has
  `sync_status == rejected`. A new `settings_update` clears it.
- `SyncEngine._isVisible` returns false for `settings_update`, so no rollback toast fires for a name.

## The re-ask (`NameReaskHost`, in Home's page)

On each arrival at Home, outside a trip, at most once per launch (memory only):

- when `nameRefused`, or `displayName == null` with `hasStartedATrip`: open `showAppSheet(NameSheet(...))`;
- `NameSheet` is the Name card's content in an `AppSheet`:
  - title `nameTitle`;
  - the field holds a fresh suggestion;
  - above the field, `nameRefusedLine` «الاسم ده مينفعش. اختار اسم تاني.» in `danger.ink` 14/600,
    only when `nameRefused`;
  - the CTA «تمام» saves as above and closes.
  - Dismissable by drag, ✕, back and the scrim.
- M14 opens the same `NameSheet` from Settings, with the current name filled in (HANDOFF §9.2).

## Strings (`app_ar.arb`)

| Key | Text |
| --- | --- |
| `nameTitle` | اسمك إيه يا أسطى؟ (replaces `destOnboardingName`'s use as the screen title) |
| `nameSubtitle` | الاسم ده هيظهر في الموقف وفي ترتيب ملك الخط. |
| `nameFieldLabel` | اسمك |
| `nameSuggestAnother` | اقترح اسم تاني |
| `nameHelper` | تقدر تغيّره بعدين من الإعدادات. |
| `nameCta` | تمام |
| `nameRefusedLine` | الاسم ده مينفعش. اختار اسم تاني. |
| `driverNameDefault` | الأسطى |
| `namePool` | the list above |
