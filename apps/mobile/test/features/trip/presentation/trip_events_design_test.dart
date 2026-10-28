import 'dart:ui' show Tristate;

import 'package:content_models/content_models.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/domain/presentation_memory.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/cards/dispute_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/boosters_row.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/overlays/banner.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/fast_forward_strip.dart';
import 'package:wassal/features/trip/presentation/overlays/hint_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/overlays/patches_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/story_strip.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/features/trip/presentation/trip_motion.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../../design/samples/c_trip.dart';
import '../../../design/samples/story_trip.dart';
import '../../../design/samples/trip_events.dart';
import '../../../design/samples/hint.dart';
import '../../../helpers/trip.dart';

// The trip's events in the new look (specs/008.5-m21-design-refresh,
// HANDOFF §11 `TripEvents`, `StoryTrip`, `Tutorial`, tasks.md T077): the
// fare banner, the ledger's badges, «أنا دافع!», the dispute, fallen notes,
// «نزّلني هنا», a story trip and بلية's hint.

const numbers = NumberFormatter(DigitStyle.arabicIndic);

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TripDashboard)));

Rect sceneOf(WidgetTester tester) =>
    tester.getRect(find.byType(GameWidget<TripGame>));

SceneLayout layoutOf(WidgetTester tester, String tripId) {
  final scene = sceneOf(tester);
  final definition = sampleTrip(tripId);
  return SceneLayout(
    definition.seats,
    vehicle: definition.vehicleId,
    width: scene.width,
    height: scene.height,
  );
}

/// The colours [finder]'s boxes are filled with.
Set<Color?> fills(WidgetTester tester, Finder finder) => {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: finder, matching: find.byType(DecoratedBox)),
  ))
    if (box.decoration case BoxDecoration(:final color)) color,
};

void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// `TripEvents`' view with its banner [elapsedMs] old.
TripView bannerAt(int elapsedMs) {
  final view = tripEventsView();
  return cTripView(
    tMs: view.banner!.shownAtMs + elapsedMs,
    banner: view.banner,
  );
}

void main() {
  group('EventBanner', () {
    testWidgets('slides down over the back window, announced once', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCTrip(tester);
      final scene = sceneOf(tester);
      final banner = find.byKey(FareBanner.bannerKey);

      await showTripView(tester, bannerAt(0));
      expect(tester.getRect(banner).top, lessThan(scene.top + 8));

      await showTripView(tester, bannerAt(1000));
      final rect = tester.getRect(banner);
      expect(rect.left, closeTo(scene.left + 10, 0.5));
      expect(rect.right, closeTo(scene.right - 10, 0.5));
      expect(rect.top, closeTo(scene.top + 8, 0.5));
      expect(rect.height, greaterThanOrEqualTo(EventBanner.minHeight));
      expect(fills(tester, banner), contains(ColorTokens.danger));
      expect(
        find.descendant(of: banner, matching: find.byKey(FareBanner.iconKey)),
        findsOneWidget,
      );
      final text = l10nOf(tester)
          .tripBannerFareUp(numbers.piasters(800), numbers.piasters(700));
      expect(find.descendant(of: banner, matching: find.text(text)), findsOne);
      // Read once: one live region with its text.
      final live = find.semantics.byPredicate(
        (n) =>
            n.getSemanticsData().flagsCollection.isLiveRegion &&
            n.label == text,
      );
      expect(live, findsOne);
      semantics.dispose();
    });

    testWidgets('holds 4 s, then goes', (tester) async {
      expect(TripMotion.bannerHold, const Duration(seconds: 4));
      expect(
        TripMotion.bannerIn * 2 + TripMotion.bannerHold,
        TripMotion.bannerTotal,
      );
      expect(TripMotion.bannerTotal.inMilliseconds, bannerMs);
      await pumpCTrip(tester);
      final scene = sceneOf(tester);
      final banner = find.byKey(FareBanner.bannerKey);
      final held =
          TripMotion.bannerIn.inMilliseconds +
          TripMotion.bannerHold.inMilliseconds;
      await showTripView(tester, bannerAt(held - 33));
      expect(tester.getRect(banner).top, closeTo(scene.top + 8, 0.5));
      await showTripView(tester, bannerAt(bannerMs));
      final gone = find.ancestor(
        of: banner,
        matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0),
      );
      expect(gone, findsOneWidget);
    });

    testWidgets('under reduced motion it fades in place', (tester) async {
      reduceMotion(tester);
      await pumpCTrip(tester);
      final scene = sceneOf(tester);
      final banner = find.byKey(FareBanner.bannerKey);
      await showTripView(tester, bannerAt(100));
      expect(tester.getRect(banner).top, closeTo(scene.top + 8, 0.5));
      final fading = find.ancestor(
        of: banner,
        matching: find.byWidgetPredicate(
          (w) => w is Opacity && w.opacity > 0 && w.opacity < 1,
        ),
      );
      expect(fading, findsOneWidget);
    });
  });

  group('the ledger peek', () {
    testWidgets('badges replace the tags, in their colours, on the tag point', (
      tester,
    ) async {
      await pumpTripEvents(tester);
      final l10n = l10nOf(tester);
      final layout = layoutOf(tester, cTripId);
      final scene = sceneOf(tester);
      for (final MapEntry(key: seatId, value: badge)
          in tripEventsLedger.entries) {
        final id = 'p_$seatId';
        expect(find.byKey(PatchesLayer.tagKey(id)), findsNothing, reason: id);
        final chip = find.byKey(LedgerBadgeChip.badgeKey(id));
        expect(chip, findsOneWidget, reason: id);
        final (text, fill, ink) = switch (badge) {
          LedgerBadge.paid => (
            l10n.tripLedgerPaid,
            ColorTokens.primary,
            ColorTokens.paper,
          ),
          LedgerBadge.unpaid => (
            l10n.tripLedgerUnpaid,
            ColorTokens.danger,
            ColorTokens.ink,
          ),
          LedgerBadge.onFriend => (
            l10n.tripLedgerOnFriend,
            ColorTokens.paper,
            ColorTokens.ink,
          ),
        };
        final label = tester.widget<Text>(
          find.descendant(of: chip, matching: find.text(text)),
        );
        expect(label.style!.color, ink, reason: id);
        expect(label.style!.fontSize, 12, reason: id);
        expect(label.style!.fontWeight, FontWeight.w700, reason: id);
        expect(fills(tester, chip), contains(fill), reason: id);
        final rect = tester.getRect(chip);
        expect(rect.height, 18, reason: id);
        final tag = layout.seats[seatId]!.tag;
        expect(
          rect.center,
          offsetMoreOrLessEquals(scene.topLeft + Offset(tag.x, tag.y)),
          reason: id,
        );
      }
    });

    testWidgets('the passengers\' labels say it too', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpTripEvents(tester);
      final l10n = l10nOf(tester);
      final label = tester
          .getSemantics(find.byKey(HitAreas.keyOf('p_B_l')))
          .label;
      expect(label, endsWith(l10n.tripLedgerOnFriend));
      semantics.dispose();
    });

    testWidgets('the booster shows active, its seconds counting down', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTripEvents(tester);
      final l10n = l10nOf(tester);
      final slot = find.byKey(BoostersRow.slotKey(BoosterId.ledgerPeek));
      expect(fills(tester, slot), contains(ColorTokens.primary));
      expect(
        find.descendant(
          of: slot,
          matching: find.text(l10n.tripSeconds(numbers.integer(4))),
        ),
        findsOneWidget,
      );
      final node = tester.getSemantics(slot);
      expect(node.label, contains(numbers.integer(4)));
      expect(node.flagsCollection.isToggled, Tristate.isTrue);

      final later = tripEventsView();
      await showTripView(
        tester,
        cTripView(
          tMs: later.tMs + 1000,
          passengers: later.passengers,
          boosters: later.boosters,
        ),
      );
      expect(
        find.descendant(
          of: slot,
          matching: find.text(l10n.tripSeconds(numbers.integer(3))),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('«أنا دافع!»', () {
    testWidgets('a popover under his face, two 44 pt buttons', (tester) async {
      await pumpTripEvents(tester);
      final l10n = l10nOf(tester);
      final layout = layoutOf(tester, cTripId);
      final scene = sceneOf(tester);
      final popover = find.byKey(ChoicesLayer.rowKey(tripEventsClaimer));
      expect(popover, findsOneWidget);
      expect(fills(tester, popover), contains(ColorTokens.paper));
      final rect = tester.getRect(popover);
      final head = layout.seats['A_m']!.head;
      expect(
        rect.center.dx,
        closeTo(scene.left + head.left + head.width / 2, 1),
      );
      expect(rect.top, greaterThan(scene.top + head.top + head.height / 2));
      expect(rect.bottom, lessThanOrEqualTo(scene.bottom - dashboardOverlap));

      for (final (insist, text, fill) in [
        (false, l10n.tripClaimAccept, ColorTokens.ground),
        (true, l10n.tripClaimInsist, ColorTokens.danger),
      ]) {
        final button = find.byKey(
          ChoicesLayer.claimKey(tripEventsClaimer, insist: insist),
        );
        expect(tester.getSize(button).height, 44, reason: text);
        expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
        expect(
          find.descendant(of: button, matching: find.text(text)),
          findsOne,
        );
        expect(fills(tester, button), contains(fill), reason: text);
      }
    });

    testWidgets('the trip keeps running', (tester) async {
      final c = await openUntilChoice(
        tester,
        'archetype__false_claimer_caught',
        (v) => v.choices.whereType<ClaimChoice>().isNotEmpty,
      );
      final claimer = c.view!.choices.whereType<ClaimChoice>().first;
      expect(
        find.byKey(ChoicesLayer.rowKey(claimer.passengerId)),
        findsOneWidget,
      );
      final before = c.view!.tMs;
      advanceMs(c, 330);
      await tester.pump();
      expect(c.view!.tMs, greaterThan(before));
      await tester.tap(
        find.byKey(ChoicesLayer.claimKey(claimer.passengerId, insist: true)),
      );
      await tester.pump();
      expect(lastCommandOf(c), ['ResolveClaim', claimer.passengerId, true]);
    });
  });

  testWidgets('the dispute: two 56 pt faces, and the trip pauses', (
    tester,
  ) async {
    final c = await openUntilChoice(
      tester,
      'event__payment_dispute',
      (v) => v.choices.whereType<DisputeChoice>().isNotEmpty,
    );
    final dispute = c.view!.choices.whereType<DisputeChoice>().first;
    for (final id in [dispute.a, dispute.b]) {
      expect(
        tester.getSize(find.byKey(DisputeCard.faceKey(id))),
        const Size.square(56),
        reason: id,
      );
    }
    final before = c.view!.tMs;
    await tester.pump(const Duration(seconds: 1));
    expect(c.view!.tMs, before);
  });

  testWidgets('a fallen note: its sun ring and a 44 pt hit area', (
    tester,
  ) async {
    final c = await openUntilChoice(
      tester,
      'event__bump_collect_and_lose',
      (v) => v.dropped.isNotEmpty,
    );
    final note = c.view!.dropped.first;
    final hit = find.byKey(DroppedLayer.noteKey(note.tokenId));
    final size = tester.getSize(hit);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    final body = tester.widget<Container>(
      find.descendant(of: hit, matching: find.byKey(MoneyNote.bodyKey)),
    );
    final shadows = (body.decoration! as BoxDecoration).boxShadow!;
    expect(shadows.map((s) => s.color), contains(ColorTokens.sunGlow));
    await tester.tap(hit);
    await tester.pump();
    expect(lastCommandOf(c), ['CollectDropped', note.tokenId]);
  });

  testWidgets('«نزّلني هنا»: the star tag', (tester) async {
    await pumpCTrip(tester);
    final passengers = cTripPassengers();
    final starred = [
      for (final p in passengers)
        if (p.seatId == 'A_l')
          PassengerView(
            passengerId: p.passengerId,
            seatId: p.seatId,
            presence: p.presence,
            look: p.look,
            slot: p.slot,
            mood: p.mood,
            talking: p.talking,
            asleep: p.asleep,
            waking: p.waking,
            headphones: p.headphones,
            attentive: p.attentive,
            nearStopPulse: true,
            dropMeHere: true,
            ledgerBadge: null,
            outcome: null,
          )
        else
          p,
    ];
    await showTripView(tester, cTripView(passengers: starred));
    expect(find.byKey(PatchesLayer.hereKey('p_A_l')), findsOneWidget);
    expect(find.byKey(PatchesLayer.tagKey('p_A_l')), findsNothing);
    expect(
      tester.getSize(find.byKey(PatchesLayer.hereKey('p_A_l'))),
      const Size.square(hereSize),
    );
  });

  group('fast-forward (trip_engine RULES.md §16)', () {
    testWidgets(
      'a dark strip at the scene\'s top while the clock runs faster',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpCTrip(tester);
        expect(find.byKey(FastForwardStrip.stripKey), findsNothing);

        await showTripView(tester, cTripView(fastForward: true));
        final l10n = l10nOf(tester);
        final scene = sceneOf(tester);
        final strip = find.byKey(FastForwardStrip.stripKey);
        final rect = tester.getRect(strip);
        expect(rect.top, closeTo(scene.top + 8, 0.5));
        expect(rect.left, closeTo(scene.left + 10, 0.5));
        expect(rect.right, closeTo(scene.right - 10, 0.5));
        expect(rect.height, 40);
        expect(fills(tester, strip), contains(ColorTokens.dashboardBg));
        final text = tester.widget<Text>(
          find.descendant(of: strip, matching: find.text(l10n.tripFastForward)),
        );
        expect(text.style!.color, ColorTokens.paper);
        expect(text.style!.fontSize, greaterThanOrEqualTo(12));
        // Two `play` glyphs, pointing the way the microbus goes in RTL.
        final glyphs = find.descendant(
          of: strip,
          matching: find.byType(AppIcon),
        );
        expect(glyphs, findsNWidgets(2));
        expect(
          tester.getRect(glyphs.first).center.dx,
          greaterThan(
            tester.getRect(find.text(l10n.tripFastForward)).center.dx,
          ),
        );
        // Read once: one live region with its text.
        final live = find.semantics.byPredicate(
          (n) =>
              n.getSemanticsData().flagsCollection.isLiveRegion &&
              n.label == l10n.tripFastForward,
        );
        expect(live, findsOne);

        // No bubble enters its band.
        for (final bubble in tester.widgetList<SpeechBubble>(
          find.byType(SpeechBubble),
        )) {
          final top = tester.getRect(find.byWidget(bubble)).top;
          expect(top, greaterThanOrEqualTo(scene.top + stripsBand(1)));
        }

        await showTripView(tester, cTripView());
        expect(find.byKey(FastForwardStrip.stripKey), findsNothing);
        semantics.dispose();
      },
    );
  });

  group('a story trip', () {
    testWidgets('the chip above the title, the dark strip for the whole trip', (
      tester,
    ) async {
      await pumpStoryTrip(tester);
      final l10n = l10nOf(tester);
      final hud = find.byType(TripHud);
      final chip = find.descendant(of: hud, matching: find.byType(StatusChip));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text(l10n.tripStoryChip)),
        findsOne,
      );
      expect(
        tester.getRect(chip).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(TripHud.titleKey)).top),
      );

      final scene = sceneOf(tester);
      final strip = find.byType(StoryStrip);
      final rect = tester.getRect(strip);
      expect(rect.top, closeTo(scene.top + 8, 0.5));
      expect(rect.left, closeTo(scene.left + 10, 0.5));
      expect(rect.right, closeTo(scene.right - 10, 0.5));
      expect(rect.height, 40);
      expect(fills(tester, strip), contains(ColorTokens.dashboardBg));
      expect(
        find.descendant(of: strip, matching: find.byKey(StoryStrip.iconKey)),
        findsOne,
      );
      final text = tester.widget<Text>(
        find.descendant(of: strip, matching: find.text(l10n.tripStoryNoFights)),
      );
      expect(text.style!.color, ColorTokens.paper);

      // No bubble enters its band.
      for (final bubble in tester.widgetList<SpeechBubble>(
        find.byType(SpeechBubble),
      )) {
        final top = tester.getRect(find.byWidget(bubble)).top;
        expect(top, greaterThanOrEqualTo(scene.top + storyBand));
      }

      await showTripView(tester, storyTripView(kept: false));
      expect(fills(tester, strip), contains(ColorTokens.danger));
    });

    testWidgets('fast-forward: its strip goes under the story strip', (
      tester,
    ) async {
      await pumpStoryTrip(tester);
      await showTripView(tester, storyTripView(fastForward: true));
      final scene = sceneOf(tester);
      final rect = tester.getRect(find.byKey(FastForwardStrip.stripKey));
      expect(rect.top, closeTo(scene.top + 8 + 40 + 8, 0.5));
      expect(rect.height, 40);
      for (final bubble in tester.widgetList<SpeechBubble>(
        find.byType(SpeechBubble),
      )) {
        final top = tester.getRect(find.byWidget(bubble)).top;
        expect(top, greaterThanOrEqualTo(scene.top + stripsBand(2)));
      }
    });

    testWidgets('a regular trip has neither', (tester) async {
      await pumpCTrip(tester);
      expect(
        find.descendant(
          of: find.byType(TripHud),
          matching: find.byType(StatusChip),
        ),
        findsNothing,
      );
      expect(find.byKey(StoryStrip.iconKey), findsNothing);
    });
  });

  group('بلية\'s hint', () {
    testWidgets('his head at the bottom-end corner, his bubble, the hand', (
      tester,
    ) async {
      await pumpHintSample(tester);
      final l10n = l10nOf(tester);
      final scene = sceneOf(tester);
      final head = tester.getRect(find.byKey(HintLayer.headKey));
      expect(head.size, const Size(96, 110));
      expect(head.right, closeTo(scene.right - 6, 0.5));
      expect(head.bottom, closeTo(scene.bottom - 22, 0.5));
      expect(
        find.descendant(
          of: find.byKey(HintLayer.headKey),
          matching: find.byType(CharacterAvatar),
        ),
        findsOneWidget,
      );

      final bubble = find.byKey(HintLayer.bubbleKey);
      final speech = tester.widget<SpeechBubble>(bubble);
      expect(speech.variant, SpeechBubbleVariant.character);
      expect(speech.name, l10n.tripHintSpeaker);
      expect(speech.text, l10n.tripHintOwed);
      final box = tester.getRect(bubble);
      expect(box.left, closeTo(scene.left + 14, 0.5));
      expect(box.right, closeTo(scene.right - 104, 0.5));

      final layout = layoutOf(tester, hintTripId);
      final face = layout.seats['A_m']!.head;
      final target = Rect.fromLTWH(
        scene.left + face.left,
        scene.top + face.top,
        face.width,
        face.height,
      );
      final hand = tester.getRect(find.byKey(HintLayer.pointerKey));
      expect(hand.size, const Size(56, 64));
      expect(hand.overlaps(target.inflate(24)), isTrue);
    });

    testWidgets('no scrim, and taps reach what is under it', (tester) async {
      await pumpHintSample(tester);
      final c = controllerOf(tester);
      expect(
        find.ancestor(
          of: find.byKey(HintLayer.bubbleKey),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .ancestor(
                    of: find.byKey(HintLayer.bubbleKey),
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            )
            .ignoring,
        isTrue,
      );
      // The bubble lies over the scene; a tap there reaches the passenger
      // hit areas or nothing, never the hint.
      final hits = tester.hitTestOnBinding(
        tester.getCenter(find.byKey(HintLayer.bubbleKey)),
      );
      expect(
        hits.path.any(
          (e) =>
              e.target is RenderObject &&
              find.byKey(HintLayer.bubbleKey).evaluate().single.renderObject ==
                  e.target,
        ),
        isFalse,
      );
      expect(c.engine, isNotNull);
    });
  });
}

/// Opens the fixture [name] and plays it until [reached].
Future<TripController> openUntilChoice(
  WidgetTester tester,
  String name,
  bool Function(TripView view) reached,
) async {
  final fixture = loadFixture(name);
  await pumpTrip(
    tester,
    tripId: fixture.definition.tripId,
    fixed: FixedTrip(
      definition: fixture.definition,
      params: fixture.params,
      seed: fixture.seed,
    ),
  );
  final c = controllerOf(tester);
  await untilView(tester, c, reached);
  return c;
}

List<Object?> lastCommandOf(TripController c) =>
    c.engine!.commandLog.last.toJson().sublist(1);
