# Feature Specification: Ads Integration — Rewarded, Interstitial, Consent (M11)

**Feature Branch**: `018-m11-ads`

**Created**: 2026-11-03

**Status**: Draft

**Input**: User description: "spec 018 — the next feature in docs/delivery-plan.md". In
`docs/delivery-plan.md` step 8, spec 018 is M11: "Ads integration: rewarded, interstitial, consent",
which depends on M05 and B07. Sources: `docs/architecture-mobile.md` §3.4 (ad placements and their
caps), §14.3 (the `ads_*` tunables), §15.1 (`AdsGateway`) and §24.3 (mediation networks);
`docs/architecture-backend.md` §8.4 (the piggy's server verification) and §22.8 (age rating and ad
content rating); the product spec's «أماكن الإعلانات»; the ux-spec's principle 5 («الإعلان اختيار، مش
عقاب»), «الإعلان البيني», the result's «اقبض ×٢», the failure card's «صالح الركاب», the boosters,
«بنزين ببلاش» and the shared states «الإعلان مش جاهز» and «حد الإعلانات اليومي خلص»; the design's
`States` 2–3 and `RewardedAdButton` (HANDOFF §3.1, §9.1 #11, Home row 6). Handed over from M02
(research "Handed to later features"): implement `TripAdOffers` for `traffic_jam` and `trip_revive`,
called only while the trip is paused or failed. From M05: the daily ad caps and the ad calls; rewards
go through `applyAdReward`. From 008.5: show `RewardedAdButton` on `Fail` and the ad badge on «زحمة»,
and remove their design-check skips. From M06: `ad_reward` already syncs; «محتاج نت» reads the
online state. From M07: no interstitial before the tutorial is done. From M08: the between-trips
checkpoint, the result's ×2 slot, Home's piggy slot and its arrival item (rank 40). From B07: the
piggy's verification options, the reward polling, the late-reward card and `ad_reward_seen`. Done
when (step 8, with B10 and B07): every placement in glossary §3.4 works with its caps enforced on the
device and on the server; no ad call is ever made while a trip is running; `morning_piggy` is granted
only through server verification; consent is collected before the first ad request.

## Clarifications

### Session 2026-11-03

- Q: Where does the free-refill ad show before M12 builds the fuel sheet? → A: M11 shows it on the
  trip's out-of-fuel card and in the placeholder fuel sheet, as one reusable piece that M12 puts
  into its sheet (User Story 5, FR-030).
- Q: Which store age group and maximum ad content rating (backend §22.8)? → A: Not designed for
  children, 13+, with the maximum ad content rating T (FR-025).
- Q: Which mediation networks (mobile §24.3)? → A: AdMob with AppLovin and Unity Ads (FR-028).
- Q: Is «اقبض ×٢» offered on the tutorial trips' results? → A: Yes, from trip 3. Trips 1–2 have no
  ads. Consent runs just before that first ad loads, and no other placement shows until the
  tutorial is done (FR-007, FR-007a).
- Q: Who designs the piggy's undrawn states? → A: The owner draws three boards: the "your piggy
  reward arrived" card, the "today's piggy is used" message and the "your reward will arrive"
  message. Implementation of those states waits for the boards (FR-018a).
- Q: What counts as a trip for the interstitial's grace period and cadence? → A: Every trip start
  the economy accepted, replays and abandoned starts included (FR-020).

## User Scenarios & Testing *(mandatory)*

Ads are the game's main income in Egypt (product spec «تحقيق الدخل»), and the design treats them as a
choice beside a decision, never a punishment (ux-spec principle 5). Five placements are rewarded and
optional; one, between trips, is a forced interstitial with strict limits. The direct users are:

- **The player**, who chooses to watch an ad for a reward, and sometimes sees an interstitial
  between trips.
- **The owner**, who earns from ads and tunes caps and frequency without a release.
- **The ad network**, which serves the ads and, for the morning piggy, tells the server the ad was
  watched.

### User Story 1 - Double the pay on the result (Priority: P1)

A player finishes a trip that paid 85 ج. Under the pay, a large blue «اقبض ×٢» button says «+١٧٠ بدل
٨٥». They tap it, watch the ad to the end, and the pay and the savings bar show 170. The button is
gone for that result. If they close the ad early, nothing changes and the button stays.

**Why this priority**: It is the placement the product spec expects most players to use, starting on
day one («أول تجربة لإعلان "اقبض ×٢"»), so it carries most of the rewarded income.

**Independent Test**: With a test ad that completes, finish a paying trip, tap «اقبض ×٢»: the wallet
grows by exactly the trip's pay, one `ad_reward` operation with `result_double` is recorded and later
accepted by the server, and the button no longer shows on that result.

**Acceptance Scenarios**:

1. **Given** a finished trip that paid more than zero and wasn't doubled, **When** the result shows,
   **Then** the ×2 offer shows with the doubled and the original amounts.
2. **Given** the offer, **When** the player watches the ad to its reward, **Then** the pay doubles
   once, the offer disappears, and the result's pay and savings show the new totals.
3. **Given** the offer, **When** the player closes the ad before its reward, **Then** nothing is
   granted and the offer stays.
4. **Given** a failed trip, a trip that paid nothing, or a result already doubled, **When** the
   result shows, **Then** there is no ×2 offer.
5. **Given** tutorial trip 1 or 2, **When** its result shows, **Then** there is no ×2 offer. From
   tutorial trip 3 on, the offer shows under the usual rules.
6. **Given** the offer and no ad ready, **When** the player looks at it, **Then** it shows the
   not-ready state («الإعلان مش جاهز») and can't be tapped, and becomes tappable when an ad loads.

---

### User Story 2 - Revive a failed trip or buy time with an ad (Priority: P1)

A player's reputation runs out three stations from the end. The failure card shows «صالح الركاب»
with the ad icon above the BONAT revive. They watch the ad, reputation comes back to 40%, and the
trip continues from the same point, paused until they tap to go on. Later, in another trip, they
have no «زحمة» left; its badge reads «إعلان». They tap it, the trip pauses, the ad plays, and when
it ends the next station gets 10 more seconds and the trip waits for them to resume.

**Why this priority**: These are the two in-trip placements, and the constitution's rule that no ad
runs during a trip (IX) is tested here. Both rewards already exist for BONAT; only the ad path is
missing.

**Independent Test**: In a trip with a spy that fails on any ad call while the engine is running,
fail the trip and take the ad revive, then use the ad «زحمة» in another trip: each reward is applied
once, each ad call happens with the engine paused or failed, and the spy never fires.

**Acceptance Scenarios**:

1. **Given** a failed trip that can be revived and hasn't been, **When** the failure card shows,
   **Then** the ad revive shows in the place the design leaves for it, above the BONAT revive.
2. **Given** the ad revive, **When** the ad's reward is earned, **Then** the trip revives exactly as
   the BONAT revive does (reputation 40%, same point), without spending BONAT.
3. **Given** a trip revived once (by ad or BONAT), **When** it fails again, **Then** no revive is
   offered.
4. **Given** a running trip with no «زحمة» in stock and no traffic-jam ad used this trip, **When**
   the dashboard shows, **Then** the «زحمة» badge shows the ad mark alongside its BONAT price.
5. **Given** the ad «زحمة», **When** the player taps it, **Then** the trip pauses before any ad call,
   the ad plays, the reward adds the time once, and the trip stays paused until the player resumes.
6. **Given** a traffic-jam ad already used this trip, **When** the dashboard shows, **Then** the ad
   mark is gone and only the BONAT price shows.
7. **Given** the ad closes early or fails to show, **When** the player returns, **Then** nothing is
   granted, the trip is paused as it was, and no BONAT is charged.

---

### User Story 3 - The morning piggy (Priority: P1)

In the morning, Home shows «حصّالة الصبح» under the savings card: «اتفرج على إعلان وخد جنيهات وبونات»
with a «ببلاش» chip. The player taps it, watches the ad, and within a few seconds a card shows the
JENEHAT and BONAT they got and the wallet pills go up. For the rest of the day the banner is gone. If
the server is slow, the app says «المكافأة في الطريق، هتلاقيها أول ما توصل», and the next time they open the game
a card tells them the piggy's reward arrived.

**Why this priority**: It is the only placement that grants BONAT, so it must go through the server
(constitution IV); B07 is merged and waiting for the app.

**Independent Test**: Against the dev backend with a test ad, tap the banner: the ad request carries
the player id and a fresh one-time reference, the app asks for that reference until the server
answers granted, the wallet is replaced by the server's, the banner hides, and the reward is
confirmed as shown so it never appears again.

**Acceptance Scenarios**:

1. **Given** the server says the piggy is available today and the phone is online, **When** Home
   shows, **Then** the banner shows under the savings card.
2. **Given** the server says it isn't available, or the phone has never heard from the server,
   **When** Home shows, **Then** the banner takes no space.
3. **Given** the banner, **When** the ad's reward is earned, **Then** the app asks the server at
   1 s, 3 s and 7 s after the reward. On "granted" it shows the amounts at once, and the wallet
   pills show the server's balances when the sync pass that the grant starts ends.
4. **Given** no answer after the last ask, **When** the app gives up, **Then** it shows
   «المكافأة في الطريق، هتلاقيها أول ما توصل» and the banner hides for the day.
5. **Given** a granted reward the player hasn't been shown (late, or the app was closed), **When**
   the next server state arrives, **Then** a card tells them the reward arrived, once, and the app
   confirms it as shown.
6. **Given** a refused answer (today's cap reached), **When** it arrives, **Then** the player sees
   that today's piggy is used, nothing is added, and the banner hides.
7. **Given** the phone is offline, **When** Home shows the banner, **Then** it is dimmed with
   «محتاج نت» and can't be tapped.

---

### User Story 4 - Interstitials between trips, within the rules (Priority: P2)

A player who has played 15 trips taps «يلا نطلع!» on Home. Three trips have passed since the last
interstitial, so one plays before the pre-trip card. A player who just doubled their pay with an ad
and taps «مشوار تاني» doesn't see one. A player who bought «شيل الإعلانات» never sees one.

**Why this priority**: Interstitials add income but the product spec limits them so they don't drive
players away; they come after the rewarded placements players choose.

**Independent Test**: Drive the between-trips checkpoint through a scripted history (trip counts,
last interstitial, last rewarded ad, entitlements, tutorial state) and check each rule decides
"show" or "pass" as glossary §3.4 says; on a device, confirm one shows only at the checkpoint.

**Acceptance Scenarios**:

1. **Given** at least 10 trips played, the tutorial done, at least 3 trips since the last
   interstitial, no rewarded ad since the last trip, and no `remove_ads` or no-interstitials
   entitlement, **When** the player goes from Home or «مشوار تاني» towards a trip, **Then** an
   interstitial shows (if one is loaded) before the pre-trip card or the trip.
2. **Given** any one of those conditions fails, **When** the player goes towards a trip, **Then**
   the checkpoint passes at once.
3. **Given** no interstitial is loaded, **When** the checkpoint would show one, **Then** it passes
   at once, and the count isn't reset.
4. **Given** «اطلع» on the pre-trip card or a running trip, **When** anything happens, **Then** no
   interstitial is ever requested there.
5. **Given** an interstitial closed, **When** it ends, **Then** the player lands where they were
   going, with nothing lost.

---

### User Story 5 - Free refill with an ad (Priority: P2)

A player's tank is empty. The fuel offer reads «اتفرج على إعلان وخد تفويلة كاملة» with «باقيلك مرتين
النهارده». They watch the ad and the tank fills. After the third today, the button is dimmed with
«خلصت النهارده» and the BONAT refill is offered beside it.

**Why this priority**: It is the escape from an empty tank that costs nothing, and the product spec
caps it at 3 a day. Where it shows depends on the fuel sheet, which is M12's.

**Independent Test**: With an empty tank and a test ad, take the refill three times in one game day:
each fills the tank, the remaining count drops, the fourth is refused on the phone, and the server
accepts the three.

**Acceptance Scenarios**:

1. **Given** a tank that isn't full and fewer than 3 refill ads today, **When** the fuel offer shows,
   **Then** the ad refill shows with how many are left today, and the BONAT refill shows beside it
   (constitution IX).
2. **Given** the ad's reward, **When** it is earned, **Then** the tank fills to its max once.
3. **Given** 3 refill ads today, **When** the fuel offer shows, **Then** the ad refill is dimmed
   with «خلصت النهارده» and the BONAT refill is offered.
4. **Given** a new game day (Cairo), **When** the fuel offer shows, **Then** the count is back to 3.
5. **Given** an empty tank at a trip start, **When** the out-of-fuel card shows, **Then** the ad
   refill shows on it, and once the reward fills the tank the player can start the trip.

The offer is one reusable piece. M11 shows it on the trip's out-of-fuel card and in the placeholder
fuel sheet (`/shop/fuel`). M12 puts the same piece into its fuel sheet (Clarifications 2026-11-03).

---

### User Story 6 - Consent before the first ad (Priority: P1)

The first time the app is about to request any ad, it asks the ad consent questions the region's law
requires (none in Egypt today, a form where one applies). No ad is requested before that. On iOS,
the tracking prompt comes before personalised ads. A player who refuses still gets ads, not
personalised.

**Why this priority**: Store and ad-network policy require it before the first ad request; the
step's "done when" names it.

**Independent Test**: On a fresh install with the consent test geography set to a region that needs
a form, reach the first ad: the form shows first, no ad request is sent before it closes, and the
answer is kept for later launches.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the app first needs an ad, **Then** consent is gathered (or
   confirmed not required) before any ad request.
2. **Given** consent refused, **When** ads are requested, **Then** they are non-personalised.
3. **Given** consent already gathered, **When** the app starts again, **Then** it isn't asked again
   unless the consent provider says it must be.
4. **Given** the first session, **When** the opening and tutorial trips 1–2 run, **Then** no
   consent form interrupts them. Consent is gathered just before the first ad loads, while trip 3
   starts, and never while a trip runs.

### Edge Cases

- **The app goes to the background during an ad** (call, home button): the ad's own outcome decides;
  a reward earned is applied once, and a trip stays paused.
- **The app is killed after the reward is earned and before it is recorded**: the reward is lost; it
  is never granted twice. For the piggy, the server's grant still arrives as a late reward.
- **A double tap on an ad button**: one ad, one reward.
- **The ad reward arrives but the economy refuses it** (the trip already revived, the tank already
  full, the result already doubled): nothing changes, and the player sees nothing alarming.
- **The server later rejects a client reward** (e.g. its own cap): M06's rollback and its single
  neutral toast apply; traffic-jam and revive rewards stay silent, as M06 decided.
- **Offline**: every ad button shows dimmed with «محتاج نت»; the interstitial checkpoint passes.
- **No ad fills** (no inventory in the region): the not-ready state shows and the BONAT alternative
  shows beside it, if there is one.
- **The phone's clock changes**: daily caps count game days on trusted time, so moving the clock
  doesn't reset them.
- **The player buys `remove_ads` mid-session**: interstitials stop from the next checkpoint; rewarded
  ads stay.
- **Reduced motion**: ad buttons use no extra motion beyond the design's states.
- **A trip resumed at launch**: no ad is requested while it is restored; the failure card's revive
  ad follows the same rules as before the restart.
- **A piggy reward refused as `not_server_placement` or `expired`**: shown as "not granted" without
  error codes, and confirmed so it doesn't come back.

## Requirements *(mandatory)*

### Functional Requirements

**Placements and caps**

- **FR-001**: The app MUST offer the six placements of glossary §3.4 (`result_double`,
  `fuel_refill`, `trip_revive`, `traffic_jam`, `morning_piggy`, `interstitial_between_trips`) and no
  others; there are no banner ads.
- **FR-002**: Every cap MUST be checked on the phone before an ad is offered: `result_double` once
  per trip result, `trip_revive` once per trip (by ad or BONAT), `traffic_jam` once per trip,
  `fuel_refill` `ads_fuel_refill_daily_cap` (3) per game day, `morning_piggy` while the server says
  it is available, the interstitial by FR-020. The daily counts MUST use game days on trusted time.
- **FR-003**: Caps and frequencies MUST come from the tunables (`ads_fuel_refill_daily_cap`,
  `ads_interstitial_every_n_trips`, `ads_interstitial_grace_trips`, `ads_morning_piggy_daily_cap`),
  with the bundled defaults when no remote value is held.
- **FR-004**: A client-applied reward MUST be recorded through the economy's ad-reward call only
  after the ad reports the reward earned, once per ad, and MUST sync as `ad_reward` like any other
  operation. `morning_piggy` MUST never be applied by the phone.
- **FR-005**: An ad closed before its reward, an ad that fails to show, and a reward the economy
  refuses MUST change nothing and MUST NOT charge BONAT.
- **FR-006**: Each ad button MUST have the design's states: ready, not ready («الإعلان مش جاهز»),
  daily limit reached («خلصت النهارده», 45% with no lip), and offline («محتاج نت»). Where a BONAT
  alternative exists, it MUST show beside the ad button in every state.
- **FR-007**: The app MUST preload an ad for a placement before it is likely to be offered, so the
  not-ready state is rare. It MUST NOT gather consent or load any ad before tutorial trip 3 starts.
- **FR-007a**: Until the tutorial is done, `result_double` is the only placement. Its offer shows on
  the results of tutorial trips 3, 4 and 5 under FR-010's rules. The other rewarded placements and
  the interstitial MUST NOT show until the tutorial is done.

**No ads during a trip (constitution IX)**

- **FR-008**: No ad call (load, show, or consent) MUST ever run while the trip engine is running. The
  in-trip placements MUST pause the engine first (`traffic_jam`) or come after the trip failed
  (`trip_revive`), and the trip MUST stay paused after the ad until the player resumes.
- **FR-009**: Tests MUST prove FR-008 with a spy that fails on any ad call while the engine runs,
  across both in-trip placements, a trip resumed at launch, and the app going to the background.

**Result ×2**

- **FR-010**: The result MUST show the ×2 offer («اقبض ×٢», «+{doubled} بدل {pay}») under the pay for
  a finished trip that paid more than zero and isn't doubled, in the slot M08 left for it, with a
  decline link at least 44×44.
- **FR-011**: After the reward, the result's pay, savings and wallet MUST show the doubled amounts,
  and the offer MUST disappear.

**In-trip ads**

- **FR-012**: The failure card MUST show the ad revive in its reserved place above the BONAT revive
  whenever the trip can be revived and hasn't been; the reward MUST revive the trip exactly as the
  BONAT revive does.
- **FR-013**: The «زحمة» booster MUST show the ad mark when none is in stock and no traffic-jam ad
  has been used this trip; the reward MUST add the booster's time once.
- **FR-014**: The design-check skips 008.5 left for the `Fail` ad revive and the «زحمة» ad badge
  MUST be removed, and those boards MUST match their designs.

**Morning piggy**

- **FR-015**: Home MUST show the piggy banner (Home row 6) only while the last server state says the
  piggy is available and the phone has heard from the server; otherwise it takes no space.
- **FR-016**: The piggy's ad MUST carry the player id and a one-time reference (a new one per ad) in
  the form the server's verification expects (B07 contracts).
- **FR-017**: After the reward, the app MUST ask the server for that reference after waits of 1 s,
  2 s and 4 s (asks at 1 s, 3 s and 7 s), treating "not found" as "not yet".
  - On "granted" it MUST show the amounts at once and start a sync pass. The wallet then shows the
    server's balances through that pass, never from the lookup's own wallet, so operations not yet
    synced are kept (research R12).
  - On "refused" it MUST say today's piggy is used.
  - After the last ask it MUST show «المكافأة في الطريق، هتلاقيها أول ما توصل».

  In each case the banner hides for the day.
- **FR-018**: For each granted reward the server lists as unseen, the app MUST show a "your piggy
  reward arrived" card once, as Home's arrival item at rank 40, and MUST then queue
  `ad_reward_seen` with its reference; it MUST also queue it after showing a grant from the polling.
- **FR-018a**: The owner draws the undrawn states:
  - the piggy reward-arrived card (FR-018);
  - the "today's piggy is used" message and the «المكافأة في الطريق، هتلاقيها أول ما توصل» message (FR-017);
  - the out-of-fuel card with the refill ad and its BONAT refill, ready and at the daily limit
    (FR-030);
  - the «زحمة» booster card with its ad button (FR-013).

  The plan MUST write a design brief for each. Each state MUST match its board, with a golden and a layout check like
  the other artboards.
- **FR-019**: No piggy amount MUST be bundled in the app; the amounts come only from the server.

**Interstitial**

- **FR-020**: The between-trips checkpoint MUST show an interstitial only when all hold: at least
  `ads_interstitial_grace_trips` (10) trips played; the tutorial done; at least
  `ads_interstitial_every_n_trips` (3) trips since the last interstitial shown; no rewarded ad
  watched since the last trip ended; no `remove_ads` and no no-interstitials entitlement; online;
  and one loaded. Otherwise it MUST pass at once. A trip, for both counts, is any trip start the
  economy accepted (one liter charged), replays and abandoned starts included.
- **FR-021**: The interstitial MUST only show at the checkpoint (from Home, «مشوار تاني» and Lines,
  before the pre-trip card or a direct start), never after «اطلع» and never during a trip.
- **FR-022**: Only a shown interstitial MUST reset its trip count; a skipped one MUST NOT.

**Consent and privacy**

- **FR-023**: The app MUST gather ad consent through the consent provider before its first ad
  request, keep the answer, and request non-personalised ads when consent is refused.
- **FR-024**: On iOS, the tracking prompt MUST come before personalised ads; refusing it MUST still
  allow non-personalised ads.
- **FR-025**: The game MUST be listed as not designed for children, 13+. Every ad request MUST set
  the maximum ad content rating to T (Teen) and MUST NOT be tagged as directed at children or as
  under the age of consent (resolves backend §22.8).
- **FR-026**: The app MUST NOT send the player id to any ad network except as the piggy's
  verification user id.

**Configuration and builds**

- **FR-027**: Dev builds MUST use Google's sample test ad units only. Staging uses the real ad units,
  because the piggy's server check works only on a real unit (B07), and serves test ads only to the
  devices registered as test devices in the AdMob console. Only prod serves live ads to everyone.
  Each flavor's app id and ad unit ids live in one per-flavor table, the way the API hosts do
  (research R4).
- **FR-028**: Mediation MUST run AdMob with AppLovin and Unity Ads, and their adapters MUST be in
  the build (resolves mobile §24.3). Each other network needs a release for its adapter, so other
  networks wait until after the Egypt beta.
- **FR-030**: The refill-ad offer MUST be one piece, shown by M11 on the trip's out-of-fuel card and
  in the placeholder fuel sheet. M12 reuses it in its fuel sheet.
- **FR-029**: Development builds MUST offer a way to show each placement with a test ad, for checks
  on the owner's phone.

### Key Entities

- **Ad placement**: one of the six identifiers in glossary §3.4, with its type (rewarded or
  interstitial), its reward and its cap.
- **Ad history (local)**: per game day, the refill ads used; the trips since the last interstitial;
  whether a rewarded ad was watched since the last trip; kept on the phone across launches.
- **Piggy reward**: a one-time reference, its state (asked, granted, refused, given up), its amounts
  from the server, and whether it has been confirmed as shown.
- **Consent state**: whether consent was gathered and whether ads may be personalised.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In automated tests, no ad call ever happens while a trip runs (0 spy failures across
  every placement and the resume and background paths).
- **SC-002**: Every placement grants its reward exactly once per completed ad, and never for an ad
  closed early, in 100% of scripted cases.
- **SC-003**: Every cap holds on the phone and is never exceeded in server-accepted operations over a
  scripted game day.
- **SC-004**: On the owner's phone with a working network, 9 in 10 piggy rewards appear within 7
  seconds of the ad closing, and every late one appears once on the next launch.
- **SC-005**: No interstitial shows in the first 10 trips, during the tutorial, right after a
  rewarded ad, or for a player with `remove_ads`, in 100% of scripted histories.
- **SC-006**: No ad request is sent before consent is gathered or confirmed not required, on a fresh
  install.
- **SC-007**: The result, `Fail`, «زحمة», Home piggy and the three new piggy boards' states match
  their designs (goldens and
  layout checks within ±2 px), with no skips left for M11.
- **SC-008**: In the first session, the opening and tutorial trips 1–2 show no ad and no consent
  form. Until the tutorial is done, the only ad offered is the ×2 on the results of trips 3–5.

## Assumptions

- B07 (merged, deployed 2026-11-03) supplies the piggy's verification, the reward lookup, the
  bootstrap `ads` block and `ad_reward_seen`; B10 supplies the tunables and entitlements.
- The server already enforces the per-trip and daily caps of `ad_reward` (B03, B07); M11 adds the
  phone-side checks and the ad calls.
- The owner draws the six boards (FR-018a) before those states are implemented. The rest
  of M11 doesn't wait for them.
- "No rewarded ad since the last trip" means a rewarded ad watched after the last trip ended blocks
  the next checkpoint's interstitial only.
- Android in Egypt is the launch target; iOS gets the same behaviour plus the tracking prompt.
- Ad revenue reporting and analytics events (`ad_offer_shown`, `ad_reward_granted`,
  `ad_interstitial_shown`) are M15's; M11 makes the events available but doesn't report them.
- The shop's `remove_ads` purchase is M12's; M11 only reads the entitlement.
- AdMob accounts, app ids, ad units and the console's mediation set-up are owner actions.
