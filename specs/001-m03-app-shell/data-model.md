# Data Model: App Shell (M03)

M03 has no server data and no database. Its "data" is a set of client-side value types: design tokens, a
route table, one device preference, the tunable registry and its bundled defaults, the build variants and
the per-tab «new» dot state. Every entity below maps to requirements in [spec.md](./spec.md).

## DesignTokens

Immutable, compile-time values exposed through the app theme. Screens read tokens, never raw values
(FR-005 – FR-008). Full values: [contracts/design-tokens.md](./contracts/design-tokens.md).

| Group | Fields | Validation |
| --- | --- | --- |
| `ColorTokens` | `shams`, `hibr`, `waraq`, `tablouh`, `primary`, `danger`, `gold`, `station1`…`station4`, `badgeNew` (alias of `danger`) | Palette test (FR-011): ΔL\* ≥ 18 for every pair in `mustDiffer`; WCAG AA for every pair in `textOnFill`; ≥ 3:1 for `badgeNew` (fill or ink outline) on `tablouh`, `shams`, `waraq`. No station color shares the danger hue. |
| `StationColor` | `fill`, `letter` (`waraq` or `hibr`) | `station1`, `station2` → white letter; `station3`, `station4` → ink letter. Letter on fill ≥ 4.5:1. |
| `TypeTokens` | `display` (Lalezar), `body` (Baloo Bhaijaan 2), scale `caption 12` … `display 32` | No style below 12 pt (FR-007). Fonts bundled as assets. |
| `ShapeTokens` | `borderCard 2.5`, `borderControl 2.5`, `radiusCard 18`, `radiusControl 14`, `shadowCard 4`, `shadowPrimary 5`, `badgeOutline 2`, `badgeSize 12` | Values in pt; shadow offset mirrors with text direction. |
| `MotionTokens` | `fast 150 ms`, `screen 250 ms`, `sheet 250 ms` | Every value < 333 ms (FR-022). With reduce-motion on, routes use `Duration.zero` or a fade. |
| `SpaceTokens` | `xs 4`, `s 8`, `m 12`, `l 16`, `xl 24`, `xxl 32` | 4-pt grid. |

## Destination

One entry per MVP route in mobile §9. Static, declared once in the route table. Full table:
[contracts/routes.md](./contracts/routes.md).

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string (unique) | Route name used by `goNamed`/`pushNamed`, e.g. `home`, `preTrip`. |
| `path` | string | go_router path pattern, e.g. `/home/pre-trip/:tripId`. |
| `presentation` | enum `tab` · `page` · `sheet` · `overlay` | Decides navigator (shell branch vs root) and page type. |
| `section` | enum `home` · `lines` · `apartment` · `shop` · `none` | Bottom-bar branch the route belongs to; `none` for root-level pages. |
| `params` | map name → validator | e.g. `tripId` must match `^line_[a-z]+\.\d{2}$` with a known `line_id`. A failing validator redirects to `/home` (FR-022). |
| `links` | list of destination names | Onward links shown on the placeholder (FR-017a). |
| `titleKey` | ARB key | Placeholder title; no literal text in source (FR-002). |

**Rules**

- `tab` destinations are exactly `home`, `lines`, `apartment`, `shop`, in that order (FR-014).
- `page`, `sheet` and `overlay` destinations sit on the root navigator, so the bottom bar is hidden
  (FR-015).
- Phase 2 and public-launch destinations are not declared (FR-017).

## DigitStyle (preference)

| Field | Type | Values | Default |
| --- | --- | --- | --- |
| `digitStyle` | enum | `arabicIndic`, `western` | `arabicIndic` |

- **Storage:** device-only key `pref.digit_style` in the `SettingsStore` (shared_preferences backend).
  Stored values: `"arabic_indic"` or `"western"`. Missing, unknown or unreadable → `arabicIndic`
  (FR-027).
- **State transitions:** `arabicIndic ⇄ western`, only from the settings control (FR-025). A change
  rebuilds every widget that formats numbers, with no restart (FR-026).
- **Read by:** `NumberFormatter` (one instance per style). See
  [contracts/number-format.md](./contracts/number-format.md).

## Tunable

A typed, keyed balancing number (constitution VIII, FR-031 – FR-035). Full key list:
[contracts/tunables.md](./contracts/tunables.md).

| Field | Type | Notes |
| --- | --- | --- |
| `key` | string | Exactly as in mobile §14.3. Per-line keys expand once per `LineId` (FR-032). |
| `type` | `int` · `bool` · `enum<string>` | Declared in the Dart registry; values only in the bundled JSON. |
| `default` | value of `type` | From `assets/config/tunables.json`. |
| `override` | optional value | From a test or the dev-only override file. Wrong type or missing → ignored. |

**Resolution order:** valid override → bundled default. M15 inserts the remote source between the two,
without changing any reader. A registry key with no bundled default, or with a default of the wrong
type, fails the test suite (FR-033).

## LineId and other glossary identifiers

Glossary §3.6 identifiers that M03 needs for route validation and per-line tunables, declared as Dart
enums whose wire names match the glossary exactly:

| Enum | Values |
| --- | --- |
| `LineId` | `line_hay`, `line_gamaa`, `line_souq`, `line_masyaf`, `line_safar` |
| `VehicleId` | `tuktuk`, `micro_old`, `micro_new`, `micro_safar` |
| `ChapterId` | `ch1_first_job` … `ch7_wedding` |
| `RoomId` | `salon`, `kitchen`, `bedroom` |

When B04 generates `packages/content_models`, these enums are replaced by the generated ones (the
generated code is the source of truth from then on).

## BuildVariant

| Variant | Application ID | App name | Tunable overrides file |
| --- | --- | --- | --- |
| `dev` | `com.wassalogra.app.dev` | «وصّل dev» | `assets/config/tunables.dev.json` (bundled only in `dev`) |
| `staging` | `com.wassalogra.app.staging` | «وصّل staging» | none |
| `prod` | `com.wassalogra.app` | «وصّل الأجرة» | none |

The variant is read at runtime from Flutter's `appFlavor`. An unknown or missing flavor at runtime is a
build error, caught by a startup assertion and a test.

## NewDotState

| Field | Type | Default |
| --- | --- | --- |
| `section` | `home` · `lines` · `apartment` · `shop` | — |
| `isOn` | bool | `false` |

- A family of providers, one per section, that defaults to off. Owning features override it later
  (FR-016a).
- **Provider:** a keep-alive `Notifier<bool>` per section, with `show()` and `clear()`.
- **Transitions:**
  - `off → on`: an owning feature calls `show()`.
  - `on → off`: the bottom bar calls `clear()` when the player opens that tab (FR-016a). Owning features
    may also clear it from their own screens.
- **Tests:** they override the provider for each section, on and off, in RTL.
