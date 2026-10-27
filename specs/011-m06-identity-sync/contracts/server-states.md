# Contract: The Server States on Screen

The offline banner, the update card, the maintenance card and the rollback toast: what triggers
them, where they sit, and their strings. The components and the `States` board's own checks are
008.5's (`OfflineBanner`, `StatusCard.update`, `StatusCard.maintenance`, `AppDialog`, `AppToast`).
This feature places them and adds their strings. Research: R14, R17–R19.

## `ServerStatus` (`lib/core/sync/server_status.dart`)

```dart
final class ServerStatusState {
  final Reach reach;                  // online | offline
  final Maintenance? maintenance;     // on(untilMs?) or null
  final UpdateState update;           // none | optional(latest) | forced
}
```

| Provider | Value | Readers |
| --- | --- | --- |
| `serverStatusProvider` | `ServerStatusState` | `HomeStatusArea`, `StatusOverlayHost` |
| `isOnlineProvider` | `bool` | later features' «محتاج نت» chips (M11, M12, M13, M14) |

Inputs: `ConnectivitySource` (M04), every `ApiResult` from `AuthorizedApi` and the auth calls, the
bootstrap's `client` block, and the sync's pass outcomes. The transitions are in data-model.md.

## Placements

| State | Widget | Where | When |
| --- | --- | --- | --- |
| Offline (`States` 1) | `OfflineBanner(message: l10n.homeOffline)` | `HomeStatusArea`, top of Home | `reach == offline` |
| Maintenance (`States` 8) | `StatusCard.maintenance(title, message, picture)` | `HomeStatusArea`, in the banner's place | `maintenance != null` and `reach == online` |
| Update, forced (`States` 7) | `AppDialog` over a `Scrim`, holding `StatusCard.update` with «حدّث من المتجر» | `StatusOverlayHost`, over every route | `update == forced`, and the trip route isn't visible |
| Update, optional | the same, plus `AppButton.tertiary` «بعدين» | `StatusOverlayHost` | `update == optional(v)`, not dismissed for `v`, not on the trip route |
| Rollback toast | `showAppToast(l10n.syncBalanceCorrected)` | the current screen | a pass with a visible rollback (R14), not on the trip route |

- **`HomeStatusArea`** (`lib/features/home/home_status_area.dart`) is a column above Home's
  content. It is empty when neither state applies, with no reserved height. Today it wraps M03's
  placeholder Home in every flavor (router `_page`), and M08 puts it on the real Home.
- **`StatusOverlayHost`** sits in `WassalApp.builder`, above the router's child. A forced card:
  - uses `PopScope(canPop: false)`;
  - doesn't close on a tap outside;
  - takes all touches beneath it.

  The trip route is read from the router, as M04's `HomeArrival` does. Fades are the components' own
  (≤ 150 ms), with no movement under reduced motion.
- **Precedence:** update over everything; offline over maintenance (HANDOFF `States` "Several states
  at once").

## `StoreLauncher` (`lib/core/platform/store_launcher.dart`)

```dart
abstract interface class StoreLauncher {
  bool get hasListing;          // false on iOS until iosAppStoreId is set
  Future<bool> openListing();   // url_launcher, LaunchMode.externalApplication
}
```

- **Android:** `https://play.google.com/store/apps/details?id=<applicationId>`, with the flavor's
  id from `AppInfo`.
- **iOS:** `https://apps.apple.com/app/id<iosAppStoreId>`. `iosAppStoreId` is an empty constant
  until the App Store listing exists (owner-actions.md). Without it, the button isn't drawn.

## Strings (`lib/l10n/app_ar.arb`)

| Key | Arabic | Source |
| --- | --- | --- |
| `homeOffline` | انت أوفلاين، المشاوير شغالة والتقدم هيتحفظ لما النت يرجع | HANDOFF `States` 1 |
| `updateTitle` | فيه نسخة جديدة | `States` 7 |
| `updateMessage` | فيها خطوط جديدة. حدّث عشان تكمّل. | `States` 7 |
| `updateCta` | حدّث من المتجر | `States` 7 |
| `updateLater` | بعدين | optional variant (not drawn; owner approves) |
| `maintenanceTitle` | الموقف بيتصلّح | `States` 8 |
| `maintenanceMessageAt` | راجعين الساعة {time}. المشاوير شغالة أوفلاين. | `States` 8; `{time}` in the player's digit style |
| `maintenanceMessage` | المشاوير شغالة أوفلاين. | `States` 8 without a time |
| `syncBalanceCorrected` | رصيدك اتظبط على آخر حساب | proposed (R14; owner approves) |

The maintenance time is the device's local time of `details.until`, as hours and minutes
(`٤:٣٠`). The digit setting decides Arabic-Indic or Western digits.

## Checks

- **Goldens** (RTL, 390×844, both digit styles), in `test/goldens/server_states_goldens_test.dart`:
  - Home with the offline banner;
  - Home with the maintenance card, with a time and without;
  - the forced update card over Home;
  - the optional card;
  - the toast over Home.
- **Layout:** each placed component matches its box on the `States` board within ±2 pt
  (`docs/design/boxes/States.json`: the banner, the update card and its button, the maintenance
  card), measured inside its placement.
- **Semantics:** the banner and the maintenance card are `liveRegion` status. The update card is a
  dialog labelled by its title. Its button is 44 pt or taller.
