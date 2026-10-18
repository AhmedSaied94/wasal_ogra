# Feature Specification: App Shell (M03)

**Feature Branch**: `001-m03-app-shell`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "M03 App shell (short name: m03-app-shell). Routing with the bottom-nav shell, theme tokens from the «ستيكر الميكروباص» palette, Arabic RTL on every screen, Arabic-Indic digits by default with a Western-digits setting. Also in scope: pin Flutter with FVM, mobile CI on GitHub Actions with goldens, and a ConfigSource with bundled defaults so tunables (constitution VIII) work before Firebase is wired up in M15. Resolve: mobile §24.1 (Android minSdk and iOS minimum). Sources: docs/ux-spec.md «النظام البصري» and «خريطة الشاشات والتنقل»; docs/architecture-mobile.md §5, §6, §9, §21. Out of scope: real screen content. Done when: the app launches in RTL with the theme tokens and both digit settings, its goldens run in CI, CI is green, and the real build/lint/test commands are added to CLAUDE.md."

## Clarifications

### Session 2026-10-18

- Q: The ux-spec station colors (#C2410C, #0F766E, #5B4B8A) have nearly the same lightness (L\* 46, 44.5,
  36), and blue #1F5FA8 vs orange #C2410C are close too (L\* 40, 46). Constitution XI requires colors
  that must be told apart to differ in lightness. How should M03 handle it? → A: The ux-spec palette is
  superseded.
  - Station colors are a 4-step lightness ladder, assigned by stop order within a trip: station.1
    #3B2A6B (L\* 22), station.2 #0F766E (L\* 44), station.3 #5FAE4E (L\* 64), station.4 #A9DDF3 (L\* 85).
    Stations 1–2 carry a white letter and 3–4 an ink letter. The letter is always shown.
  - Primary blue becomes #1A4B8C (L\* 32) and danger becomes #F2542D (L\* 57.5). Gold stays #F5B301.
  - No station color may reuse the danger hue.
  - M03 defines these as theme tokens and adds a test that asserts ΔL\* ≥ 18 between colors that must be
    told apart, and WCAG contrast for every text-on-fill pair.
  - A trip has at most 4 drop-off stations until a second channel (shape) is specified for the travel
    line.
- Q: How should a tester (and later the player) reach the nested placeholder destinations? → A: Each
  placeholder links onward along the ux-spec navigation map, and later features keep these links when
  they replace a placeholder. There is no debug-only route index.
- Q: When a player turns up their phone's font size, up to what size should the app's text grow? → A:
  Up to 1.3×. Larger settings are capped at 1.3×, and settings smaller than default are treated as 1.0×.
- Q: What should the phone's back button do on الموقف (Home)? → A: Press back twice to leave. The first
  press shows a short «press again to leave» message, and a second press within 2 s leaves the app.
- Q: Which phone should the M03 cold-start check be measured on? → A: Choose the reference device now;
  M03 owns the decision and resolves mobile §24.2.
  - Reference device: Samsung Galaxy A06, 4 GB RAM, Helio G85.
  - SC-001 is measured on it with the `prod` variant in release mode: force-stop, then
    `adb shell am start -S -W`, 10 runs. The app calls `reportFullyDrawn()` when الموقف renders its
    first frame. Pass means a median of 3.0 s or less.
  - "No white frame" means the splash screen, the launch theme and the first Flutter frame all use شمس
    #FFD23F. It is verified by a screen recording of the launch in which no frame is mostly pure white.
  - An optional 3 GB Unisoc device is checked once per release, but it is not a gate.
- Q: The ux-spec puts a red «new» dot on tabs, but the palette has no red. What color is it, and does
  the bottom bar support it now? → A:
  - The dot uses a token badge.new, an alias of danger (#F2542D), with a 2 pt ink (#1D1A2B) outline,
    12 pt across in total.
  - It sits at the icon's top-end corner (top-left in RTL) and is announced as «جديد» to screen readers.
  - The outline keeps it at least 3:1 on the dark bar, the شمس background and white cards.
  - M03 ships a shared dot component and a per-tab on/off input that defaults to off. Owning features
    turn it on later, and a dot clears when the player opens that tab or screen.
  - No dev index (the earlier decision stands) and no in-app switch. Widget and golden tests override
    the per-tab input, with each tab on and off, in RTL.
  - The first feature that turns a dot on adds an acceptance check that the dot appears and clears.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - First open looks and reads like the game (Priority: P1)

A player installs the app and opens it. From the very first frame they see the taxi-yellow background
(no white flash), then الموقف (Home, a placeholder for now) with the dark bottom bar. Everything reads
right to left in Egyptian Arabic, whatever language the phone is set to, and uses the
«ستيكر الميكروباص» colors, fonts, thick ink borders and hard shadows.

**Why this priority**: Every later screen is built on top of this shell. RTL and the visual system
added late show up as broken layouts (constitution X), so they come first.

**Independent Test**: Install a fresh build on a phone set to English, open it, and check that no
white frame appears, that الموقف shows in Arabic right to left with the four-tab bottom bar, and that
colors, fonts, borders and shadows match the tokens in this spec.

**Acceptance Scenarios**:

1. **Given** a fresh install on a phone whose language is English, **When** the player opens the app,
   **Then** every screen is in Arabic and laid out right to left.
2. **Given** the app is starting, **When** the first frame appears, **Then** the background is شمس
   (#FFD23F), and no white or black frame shows before الموقف.
3. **Given** the phone is in dark mode, **When** the app opens, **Then** it looks exactly as it does in
   light mode.
4. **Given** the app is open, **When** the player rotates the phone, **Then** the app stays in portrait.
5. **Given** any screen the shell ships, **When** it is measured, **Then** every touch target is at
   least 44×44 pt and every piece of text is at least 12 pt.

---

### User Story 2 - Moving around the game (Priority: P2)

The player moves between the four main sections with the bottom bar, opens full-screen pages and
bottom sheets, and always knows how to get back: the back control sits at the top right, the phone's
back button does the same thing, and back inside a trip opens the pause overlay instead of leaving.

**Why this priority**: The navigation rules in ux-spec «قواعد التنقل» apply to every screen. Building
them once, with placeholder destinations, means each later feature only fills in its own screen.

**Independent Test**: Starting from الموقف and tapping only the placeholders' links, a tester visits
every MVP destination in mobile §9 (except onboarding, which M07 links), checks that the bottom bar
appears only on the four section screens, closes each sheet both by swiping down and with its close
button, and gets back to الموقف with back from everywhere.

**Acceptance Scenarios**:

1. **Given** الموقف is open, **When** the player taps الخطوط, الشقة or المحل in the bottom bar,
   **Then** that section opens with its tab highlighted, and the tabs read from right to left as
   الموقف، الخطوط، الشقة، المحل.
2. **Given** the player has scrolled or moved deeper inside a section, **When** they switch to another
   tab and come back, **Then** the section is exactly as they left it.
3. **Given** a full-screen page (such as settings, the trip, the result or the story viewer) or a sheet
   is open, **When** the player looks at the screen, **Then** the bottom bar is not shown.
4. **Given** a sheet is open (pre-trip card, line detail, vehicle purchase, apartment item, family
   requests or fuel), **When** the player swipes it down or taps its close button, **Then** it closes
   and the screen under it is unchanged.
5. **Given** any screen other than the four section screens and the trip, **When** the player taps the back control
   at the top right or presses the phone's back button, **Then** the app returns to the previous screen.
6. **Given** the trip placeholder is open, **When** the player presses back, **Then** the pause overlay
   opens and the trip stays underneath; **When** they press back again, **Then** the pause overlay
   closes and the trip is shown again.
7. **Given** الخطوط, الشقة or المحل is open at its top level, **When** the player presses the phone's
   back button, **Then** الموقف opens.
8. **Given** الموقف is open, **When** the player presses the phone's back button once, **Then** a short
   message asks them to press again to leave and the app stays open; **When** they press it again within
   2 s, **Then** the app leaves to the phone's home screen; **When** they don't, **Then** the message
   disappears and nothing else happens.

---

### User Story 3 - Choosing how numbers look (Priority: P3)

Numbers show in Arabic-Indic digits (١٢٣) by default. In settings, the player can switch to Western
digits (123). The change applies at once on every screen and is remembered next time, with or without
a network.

**Why this priority**: Required by the product spec «الإعدادات» and constitution X. Some players,
especially in the Gulf, read Western digits more easily. Every later screen shows numbers, so the
formatting must exist before them.

**Independent Test**: Open the settings placeholder, switch the digit setting, check the sample numbers
on every shell screen, then restart the app offline and check that the choice is kept.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** any number is shown, **Then** it uses Arabic-Indic digits.
2. **Given** settings is open, **When** the player chooses Western digits, **Then** every number on
   every screen switches to Western digits immediately, with no restart.
3. **Given** the player chose Western digits, **When** the app is closed and reopened with no network,
   **Then** numbers are still in Western digits.
4. **Given** each digit style, **When** these values are shown, **Then** they read as follows:

   | Value | Arabic-Indic | Western |
   | --- | --- | --- |
   | 850 piasters | ٨٫٥ | 8.5 |
   | 700 piasters | ٧ | 7 |
   | 1,250 pounds | ١٬٢٥٠ | 1,250 |
   | a 750-second countdown | ١٢:٣٠ | 12:30 |
   | 4 out of 5 | ٤/٥ | 4/5 |
   | minus 1 | −١ | −1 |

5. **Given** Western digits inside an Arabic sentence (for example «−1 بنزين»), **When** it is shown,
   **Then** the sign, the number and the words appear in the correct reading order.

---

### User Story 4 - Balancing numbers work offline from day one (Priority: P4)

Every balancing number (hop and bubble timings, reputation deltas, fuel, ad caps and the rest of
mobile §14.3) has a default that ships inside the app. Every feature reads these numbers from one
shared place. When remote tuning is wired up in M15, it can override any default without changing the
features that read it.

**Why this priority**: Constitution VIII forbids hard-coded balancing numbers. The next features (the
trip engine parameters, fuel, ads) need these values before remote tuning exists.

**Independent Test**: On a device that has never been online, read every key in mobile §14.3 and
compare it with the documented default; override one key in a test and check that only that key
changes; give a key a value of the wrong type and check that the default is used.

**Acceptance Scenarios**:

1. **Given** a device that has never been online, **When** any key listed in mobile §14.3 is read,
   **Then** it returns the documented default.
2. **Given** a per-line key (such as `trip_hop_ms_<line_id>`), **When** it is read for any `line_id` in
   glossary §3.6, **Then** a default exists for that line.
3. **Given** a test or dev build overrides one key, **When** that key is read, **Then** the override is
   returned and every other key keeps its default.
4. **Given** an override is missing or has the wrong type, **When** the key is read, **Then** the
   bundled default is returned and the app keeps running.

---

### User Story 5 - Every change is checked automatically (Priority: P5)

Every pull request that touches the mobile app is checked automatically: static analysis, formatting,
unit, widget and golden tests (RTL, both digit styles), the color checks, the coverage threshold and an
Android build, all with the same pinned toolchain version on every machine. Contributors find the real
commands in `CLAUDE.md`.

**Why this priority**: The constitution's CI gates must exist before the first feature code lands on
`master`. Without them, the RTL, size and color rules can't be enforced.

**Independent Test**: Open one pull request that changes a theme color, and another that puts Arabic
player text directly in source code. Both are blocked. A clean pull request passes.

**Acceptance Scenarios**:

1. **Given** a pull request changes mobile code, **When** it is opened or updated, **Then** the checks
   run and report pass or fail on the pull request.
2. **Given** a change alters how any shell screen looks, **When** the checks run, **Then** a golden test
   fails until the reference images are updated on purpose.
3. **Given** a change moves two colors that must be told apart closer than ΔL\* 18, or makes a text
   color fail contrast on its fill, **When** the checks run, **Then** they fail.
4. **Given** line coverage of the app drops below 80%, **When** the checks run, **Then** they fail.
5. **Given** player-visible Arabic text is written in source code instead of the translation files,
   **When** the checks run, **Then** they fail.
6. **Given** a developer's installed toolchain differs from the pinned version, **When** they use the
   commands in `CLAUDE.md`, **Then** the pinned version is used, or the mismatch is reported.
7. **Given** a new contributor reads `CLAUDE.md`, **When** they follow it, **Then** they can build, run,
   lint and test the app and update the golden images.

---

### Edge Cases

- **Phone language is not Arabic** (English, French, any other): the app is still Arabic and RTL.
- **Phone set to dark mode**: the app looks the same as in light mode (ux-spec «النظام البصري»).
- **Large or small system text size**: text grows with the phone's setting up to 1.3× and stops there.
  At 1.3× nothing overflows or gets cut off. Settings smaller than default are treated as default, so
  text never drops below 12 pt.
- **Small phone (360×640 pt)**: no overflow, and the bottom bar and every touch target keep their
  minimum sizes.
- **Notch, punch-hole camera or gesture navigation**: content stays inside the safe area, and the
  bottom bar sits above the gesture area.
- **Reduce-motion turned on in the phone**: screen transitions don't slide or bounce.
- **Rapid double tap on a tab or a button that opens a page**: only one copy of the page opens.
- **Back while a sheet is open**: only the sheet closes.
- **Accidental back on الموقف**: one press only shows the «press again to leave» message. A second press
  more than 2 s later counts as a new first press.
- **Unknown or malformed destination** (for example a bad trip id): الموقف opens instead of a blank
  screen or a crash.
- **App killed while on another tab**: the next cold start opens on الموقف.
- **Stored digit choice missing or unreadable**: Arabic-Indic digits are used and the app keeps running.
- **Tunable override missing or of the wrong type**: the bundled default is used.
- **Text on the danger color**: white reaches only 3.45:1 on #F2542D, so text on danger fills is ink
  (4.92:1).

## Requirements *(mandatory)*

### Functional Requirements

#### Language and direction

- **FR-001**: Every screen MUST be laid out right to left and shown in Egyptian Arabic, regardless of
  the phone's language or region.
- **FR-002**: All player-visible text, including placeholder labels, MUST come from the app's
  translation resources. No player-visible text may appear in source code (constitution VII).
- **FR-003**: Directional elements (back arrows, chevrons, slide transitions, swipe directions) MUST
  follow RTL and MUST NOT assume left-to-right flow.
- **FR-004**: The app MUST run in portrait only.

#### Visual system («ستيكر الميكروباص»)

- **FR-005**: The app MUST define the palette once, as named tokens with their usage roles. This palette
  supersedes the values in ux-spec «الألوان»:

  | Token | Value | Use |
  | --- | --- | --- |
  | شمس | #FFD23F | screen background, the «حد معاه فكة؟» button |
  | حبر | #1D1A2B | borders, text, hard shadows |
  | ورق | #FFFFFF | cards and speech bubbles |
  | تابلوه | #2A2633 | dashboard and bottom bar background |
  | أزرق (primary) | #1A4B8C | primary buttons, exact money, progress |
  | برتقالي (danger) | #F2542D | danger: station approaching, fight, shortage |
  | ذهبي | #F5B301 | coins and stars |
  | station.1 … station.4 | see FR-010 | station patches, by stop order |
  | badge.new | alias of danger (#F2542D) | the «new» dot (FR-016a) |

  No screen may use a color that is not a token.
- **FR-006**: The app MUST define shape and motion tokens from ux-spec «المكونات المشتركة» and
  «الحركة والصوت والاهتزاز»: card border 2.5 pt, card corner radius 18 pt, hard shadow 4 pt on cards
  and 5 pt on the primary button, and interface motion shorter than ⅓ s. No screen may use its own
  border, radius, shadow or duration values.
- **FR-007**: The app MUST define two typefaces as tokens: a street-sign display face for titles and
  big buttons, and a rounded, readable face for body text and numbers (ux-spec «الخطوط»). The fonts
  MUST ship inside the app so they render with no network. No text style may be smaller than 12 pt.
- **FR-008**: The shell MUST provide the shared components it needs, built only from tokens as
  described in ux-spec «المكونات المشتركة»: the primary button, the secondary button, the card, the
  bottom bar and the «new» dot. Later features reuse them instead of styling their own.
- **FR-009**: The app MUST look the same whether the phone is in light or dark mode.
- **FR-010**: Station colors MUST be a four-step lightness ladder, assigned by stop order within a trip:

  | Token | Value | Lightness (CIE L\*) | Letter color |
  | --- | --- | --- | --- |
  | station.1 | #3B2A6B | 22 | white |
  | station.2 | #0F766E | 44 | white |
  | station.3 | #5FAE4E | 64 | ink |
  | station.4 | #A9DDF3 | 85 | ink |

  The station letter MUST always be shown with the color. No station color may reuse the danger hue.
- **FR-011**: An automated check MUST verify the palette:
  - ΔL\* ≥ 18 between every pair of colors that must be told apart: each pair of station colors, and
    primary vs danger;
  - WCAG 2.1 AA contrast (4.5:1 for normal text, 3:1 for large text) for every text-on-fill pair the app
    uses, including each station letter on its station color;
  - at least 3:1 contrast for the «new» dot, through its fill or its ink outline, on the تابلوه bar, the
    شمس background and white cards.
- **FR-012**: From the moment the player taps the app icon, the background MUST be شمس (#FFD23F): the
  system splash screen, the launch theme and the app's first frame all use it. No white or black frame
  may appear before the first screen. The boot screen shows the game's name on شمس and moves on to
  الموقف as soon as the app is ready.
- **FR-012a**: When الموقف renders its first frame after a cold start, the app MUST report to the
  operating system that it is fully drawn, so launch time can be measured the same way every time.
- **FR-013**: The same change MUST update ux-spec «الألوان» (and any other doc that lists the old blue,
  orange or per-station colors) to the palette in FR-005 and FR-010, so the docs don't silently diverge
  from the tokens.

#### Navigation

- **FR-014**: The bottom bar MUST have exactly four tabs, from right to left: الموقف، الخطوط، الشقة،
  المحل. It uses the تابلوه color, and الموقف is selected at launch.
- **FR-015**: The bottom bar MUST appear only on the four section screens. It MUST be hidden on
  full-screen pages, sheets and overlays (ux-spec «قواعد التنقل»).
- **FR-016**: Each section MUST keep its state (scroll position, deeper pages) when the player switches
  tabs and returns.
- **FR-016a**: Each bottom-bar tab MUST be able to show the «new» dot. The dot:
  - uses the badge.new color with a 2 pt ink (#1D1A2B) outline, 12 pt across in total;
  - sits at the icon's top-end corner (top-left in RTL);
  - is announced as «جديد» to screen readers, with the word taken from the translation resources;
  - is off by default, driven by a per-tab on/off input that the owning features turn on later;
  - clears when the player opens that tab or screen.

  There is no in-app switch for the dots in any build. Tests turn them on.
- **FR-017**: Every MVP destination listed in mobile §9 MUST exist as a labeled placeholder, with the
  presentation that table gives it (section tab, full-screen page, sheet or overlay). Destinations
  planned for phase 2 or public launch (garage, leagues, seasonal events, referral) MUST NOT be added.
- **FR-017a**: Each placeholder MUST link onward along the ux-spec navigation map, so every destination
  can be reached by tapping, starting from الموقف:
  - الموقف → pre-trip sheet → trip (with its pause overlay) → result → الموقف or the pre-trip sheet
    again;
  - الموقف → settings → account;
  - الموقف → daily reward, daily tasks, daily challenge;
  - الخطوط → line detail sheet → vehicle purchase sheet;
  - الشقة → item sheet, family requests sheet, chapters → story viewer;
  - المحل → fuel sheet.

  Later features keep these links when they replace a placeholder. There is no debug-only route index.
  The onboarding destinations (intro, driver name) are the one exception: M07 links them to the first
  launch, so in this feature only tests open them directly.
- **FR-018**: Sheets MUST open from the bottom and close either by swiping down or with a close button.
- **FR-019**: Every screen other than the four section screens and the trip MUST show a back control at
  the top right. The phone's back button MUST do the same thing as that control. The trip is the
  exception: during a trip, everything the player touches sits in the bottom third (constitution XI),
  so the trip has no top-right control. Its back is the phone's back button, which opens the pause
  overlay (FR-020).
- **FR-020**: On the trip destination, back (either control) MUST open the pause overlay and MUST NOT
  leave the trip. Back on the pause overlay closes it. The pause placeholder also offers a way to return
  to الموقف.
- **FR-021**: The phone's back button on the top level of الخطوط, الشقة or المحل MUST open الموقف. On
  الموقف, the first press MUST show a short message asking the player to press again to leave, and the
  app MUST leave only if back is pressed again within 2 s. Otherwise the message disappears and the app
  stays on الموقف. The message text comes from the translation resources (FR-002).
- **FR-022**: An unknown or malformed destination MUST open الموقف instead of an error or a blank
  screen.
- **FR-023**: Screen transitions MUST take less than ⅓ s. When the phone's reduce-motion setting is on,
  transitions MUST NOT slide or bounce.
- **FR-024**: Repeated taps on a tab or on a control that opens a page MUST NOT open the same page more
  than once.

#### Digits and number formatting

- **FR-025**: The app MUST offer a digit style setting with two options: Arabic-Indic (١٢٣), the
  default, and Western (123). In this feature, the settings placeholder holds only this control; M14
  builds the rest of settings around it.
- **FR-026**: Changing the digit style MUST update every number on every screen immediately, with no
  restart.
- **FR-027**: The digit style MUST be remembered across restarts and MUST work with no network. If the
  stored choice is missing or unreadable, Arabic-Indic is used.
- **FR-028**: Every player-visible number MUST go through one shared formatter. It covers whole
  numbers, counts and fractions (٤/٥, ٢٧ من ٩٠), countdowns (١٢:٣٠), signed numbers (−١), and money
  amounts given in integer piasters and shown in pounds (850 → ٨٫٥). The decimal and thousands
  separators follow the digit style (٫ and ٬ for Arabic-Indic, . and , for Western). The formatter
  accepts integers only for money (constitution II).
- **FR-029**: Numbers inside Arabic sentences MUST keep the correct reading order in both digit styles.
- **FR-030**: Text MUST follow the phone's text-size setting between 1.0× and 1.3×. Larger settings are
  capped at 1.3×, and smaller ones are treated as 1.0×, so text never drops below 12 pt. No layout may
  overflow or cut off text at 1.3×.

#### Tunable numbers

- **FR-031**: Every key listed in mobile §14.3 MUST have a default that ships inside the app and is
  readable from the first launch with no network.
- **FR-032**: Per-line keys MUST have a default for every `line_id` in glossary §3.6, matching the
  values in mobile §14.3 and ux-spec «الصعوبة والمساعدة حسب الخط».
- **FR-033**: Each key MUST have a declared type and default. Reading a key that has no default, or
  reading it as the wrong type, MUST be caught by automated checks before merge.
- **FR-034**: Features MUST read tunable numbers through one shared configuration entry point and never
  from a remote service directly. A remote source added later (M15) MUST be able to override any default
  without changing the features that read it.
- **FR-035**: Tests and the dev build MUST be able to override any key. A missing or wrongly typed
  override falls back to the bundled default.

#### Build, platforms and checks

- **FR-036**: The toolchain version MUST be pinned in the repository, so every developer machine and
  the automated checks build with the same version.
- **FR-037**: The app MUST have three build variants, `dev`, `staging` and `prod` (mobile §21). They can
  be installed side by side on one phone and have distinguishable names.
- **FR-038**: The app MUST declare its minimum supported Android and iOS versions. The proposal is
  Android 7.0 (API level 24) and iOS 15. The final values are confirmed against the minimums of every
  MVP dependency in this feature's research (mobile §24.1), and mobile §2 and §24.1 are updated to match.
- **FR-039**: Every pull request and every push to `master` that touches the mobile app MUST run
  automated checks: static analysis with no issues, a formatting check, unit, widget and golden tests,
  the palette check (FR-011), line coverage of at least 80%, and a `dev` Android build. Any failure
  blocks the merge.
- **FR-040**: Golden tests MUST cover every screen the shell ships (boot, the four sections with the
  bottom bar, a full-screen placeholder, a sheet placeholder, the pause overlay, and settings) in RTL,
  in both digit styles, at the reference frame 390×844 pt and on a small phone (360×640 pt), at text
  scale 1.0× and 1.3×. Every MVP destination and the pause overlay are also covered at 390×844 pt and
  text scale 1.0×, in both digit styles (constitution X). Widget and golden tests also cover each tab
  with the «new» dot on and off, in RTL, by overriding the per-tab dot input.
- **FR-041**: Automated tests MUST check that every touch target in the shell is at least 44×44 pt and
  every text at least 12 pt.
- **FR-042**: An automated check MUST fail when player-visible Arabic text appears in source code
  outside the translation resources.
- **FR-043**: `CLAUDE.md` MUST list the real commands to build, run, lint and test the app and to update
  golden images, replacing the "no commands yet" note.
- **FR-044**: This feature resolves mobile §24.2. The same change MUST record the reference device
  (Samsung Galaxy A06, 4 GB RAM, Helio G85) in mobile §2, §19 and §24.2, and move §24.2 from step 5 to
  step 1 in `docs/delivery-plan.md`.

### Key Entities *(include if feature involves data)*

- **Design token**: a named visual value (color, typeface, text size, border, radius, shadow, motion
  duration) with its usage role. Screens refer to tokens, never to raw values.
- **Station color**: one of four tokens on a lightness ladder, paired with a letter color. A trip
  assigns them to its drop-off stations by stop order, not by station identity.
- **Destination**: a place in the app the player can reach. It has a name, a presentation (section tab,
  full-screen page, sheet or overlay), a roadmap phase, and parameters such as `tripId` or `lineId`.
- **«New» dot state**: one on/off value per bottom-bar tab. It defaults to off, is set by the feature
  that owns the tab's content, and clears when the player opens the tab or screen.
- **Digit style preference**: the player's choice of Arabic-Indic or Western digits. It is stored on
  the device, defaults to Arabic-Indic, and is read by the shared number formatter.
- **Tunable**: a balancing number with a key from mobile §14.3, a type, a bundled default, and an
  optional override. The current value is the override if valid, otherwise the default.
- **Build variant**: `dev`, `staging` or `prod`, each with its own app name and identity so they can be
  installed together.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the reference device (Samsung Galaxy A06, 4 GB RAM, Helio G85), with the `prod` variant
  in release mode, the median cold start to الموقف over 10 runs is at most 3.0 s. Each run force-stops
  the app first, and time is taken up to the app's fully-drawn report (FR-012a). An optional 3 GB
  Unisoc phone is checked once per release, but it is not a gate.
- **SC-001a**: A screen recording of a cold start on the reference device shows no frame that is mostly
  pure white.
- **SC-002**: 100% of shell screens show Arabic, right to left, when the phone's language is English,
  French or Arabic.
- **SC-003**: After the player changes the digit style, 100% of the numbers on the current screen show
  the new style without a restart, and the choice survives 100% of restarts, online or offline.
- **SC-004**: Across all shell screens, in both digit styles and at text scale 1.0× and 1.3×, there are
  0 touch targets under 44×44 pt, 0 texts under 12 pt, and 0 overflowing layouts.
- **SC-005**: 100% of the text-on-fill pairs the app uses meet WCAG 2.1 AA contrast, and 100% of the
  pairs of colors that must be told apart differ by at least 18 in lightness (ΔL\*).
- **SC-006**: Starting from الموقف, a tester can reach every MVP destination in mobile §9 except
  onboarding by tapping placeholder links, get back to الموقف using only the back control or the
  phone's back button, and sees the bottom bar only on the four section screens.
- **SC-007**: On a phone that has never been online, 100% of the keys in mobile §14.3 return their
  documented defaults.
- **SC-008**: Every mobile pull request gets a pass or fail result from the automated checks within
  15 minutes, and a deliberately broken golden, failing test, palette violation or Arabic literal in
  source blocks the merge every time.
- **SC-009**: A contributor new to the repository can build, run and test the app using only the
  commands in `CLAUDE.md`, on the first attempt.
- **SC-010**: Line coverage of the app is at least 80%.

## Assumptions

- **Players and devices**: players read Arabic and use phones. Tablets show the same portrait phone
  layout; there are no tablet-specific layouts in the MVP.
- **Fonts**: the prototype's fonts are kept, Lalezar for display and Baloo Bhaijaan 2 for body text and
  numbers. Both are free to bundle in a commercial app (SIL Open Font License) and include Arabic-Indic
  digits.
- **Placeholders**: each MVP destination shows a simple card with its name, its parameters and its
  onward links (FR-017a), built from the shared components. Later features replace the placeholder
  with the real screen.
- **Boot and first launch**: in this feature, boot always goes straight to الموقف. The animated loading
  screen and the first-launch onboarding route (intro, name, tutorial) come with M07.
- **Cold start**: the app always opens on الموقف. It does not restore the last tab.
- **Number formatting**: thousands are grouped (١٬٢٥٠ / 1,250), and the minus sign is a true minus (−).
- **Digit style storage**: the choice is stored on the device only. Whether it should also sync with the
  account is left to M06 and M14.
- **Derived colors**: lighter and darker variants that the ux-spec derives from the orange (the warning
  and fight bubbles) are derived from the new danger color in the features that use them (M02), and
  pass the same palette check.
- **Tunables**: no remote source exists yet. M15 adds remote tuning, and B10 adds the server's matching
  copies (`liveops.LiveSetting`). This feature adds no new tunable keys.
- **Minimum OS versions**: the floor is set by the toolchain and the MVP dependencies (ads, purchases,
  analytics, animation), not by a product choice. The plan's research checks each one at its pinned
  version and picks the lowest level they all support.
- **Tools**: the toolchain, the CI service and the state, routing and storage libraries are fixed by the
  constitution's locked stack and `CLAUDE.md`. The plan names them.
- **Dependencies**: none. B01 (backend skeleton) runs in parallel and shares no artifact with this
  feature.
- **«New» dot in later features**: the first feature that turns a dot on adds an acceptance check that
  the dot appears and clears when its tab or screen is opened.
- **Trip pause control (for M02)**: ux-spec «الشريط العلوي» puts the trip's pause button at the top
  right, which conflicts with constitution XI (bottom third). M02 resolves it, either by moving the pause
  control into the bottom third or by amending the constitution through `/speckit-constitution`. M03's
  trip placeholder follows the constitution.
- **Constraint for later features**: a trip has at most 4 drop-off stations, one per station color,
  until a second channel (shape) is specified for the travel line (`line_safar`). B04's trip schema and
  content validation enforce this limit, and M02 assigns station colors by stop order.
- **Out of scope**:
  - real content for any screen (home, trip, lines, apartment, shop, settings beyond the digit control);
  - the trip scene, the trip engine and content packs;
  - network calls, accounts and sync;
  - analytics, crash reporting and remote tuning (M15);
  - ads and purchases;
  - iOS builds and iOS CI, which start with the iOS launch in phase 3 (only the current roadmap phase
    is built);
  - release signing and store uploads.
