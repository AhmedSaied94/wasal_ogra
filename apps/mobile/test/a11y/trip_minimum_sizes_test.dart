import 'package:flame/game.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/coach_layer.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/hint_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/patches_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/top_bar/station_strip_bar.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/content.dart';
import '../helpers/economy.dart';
import '../helpers/screens.dart';
import '../helpers/trip.dart';
import '../helpers/tutorial_content.dart';
import 'minimum_sizes_test.dart' show effectiveFontSizes, minTextSize;

// The trip screen's minimum sizes (specs/008.5-m21-design-refresh,
// contracts/trip-layout.md "Guaranteed sizes", "Text scale"; constitution
// XI): faces, hit areas, notes, bubble text, dashboard targets, text,
// contrast, labels, the 1.15 clamp, nothing overlapping or cut short, and
// every control outside the scene in the bottom third, on the four trip
// surfaces in the US1–US6 states; under the threshold, in the compact
// profile (specs/012-m07-onboarding, contracts/compact-trip-layout.md
// "Guaranteed sizes (compact)"), and with بلية's coach on screen there.

/// Where [node] sits on the screen.
Rect globalRect(SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    if (n.transform case final t?) rect = MatrixUtils.transformRect(t, rect);
  }
  return rect;
}

/// Every node a screen reader can tap.
List<SemanticsNode> tappable(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  bool visit(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
      nodes.add(node);
    }
    node.visitChildren(visit);
    return true;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}

/// The paragraphs drawn under the widgets [of] finds.
List<RenderParagraph> paragraphsIn(WidgetTester tester, Finder of) => [
  for (final e
      in find.descendant(of: of, matching: find.byType(RichText)).evaluate())
    if (e.renderObject case final RenderParagraph p when p.hasSize) p,
];

Rect paragraphRect(RenderParagraph p) => p.localToGlobal(Offset.zero) & p.size;

void main() {
  for (final state in [
    ...us1TripCases(),
    ...us2TripCases(),
    ...us3TripCases(),
    ...us4TripCases(),
    ...us5TripCases(),
    ...us6TripCases(),
  ]) {
    for (final surface in TripSurface.values) {
      for (final scale in textScales) {
        testWidgets('${state.name} · ${surface.name} · ×$scale', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          await openTripCase(tester, state, surface: surface, textScale: scale);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(TripDashboard)),
          );
          final height = surface.size.height;

          // The bands keep their profile's sizes on every surface.
          expect(
            tester.getSize(find.byType(TripHud)).height,
            surface.compact ? compactHudHeight : tripHudHeight,
          );
          expect(
            tester.getSize(find.byType(TripDashboard)).height,
            surface.compact ? compactDashboardHeight : dashboardHeight,
          );

          // Faces, from the layout the scene and the overlays share: kept
          // on every surface.
          final c = controllerOf(tester);
          final definition = c.session?.facts.definition;
          if (definition != null) {
            final scene = tester.getRect(find.byType(GameWidget<TripGame>));
            final layout = SceneLayout(
              definition.seats,
              vehicle: definition.vehicleId,
              width: scene.width,
              height: scene.height,
            );
            expect(layout.scale, 1);
            for (final seat in layout.seats.values) {
              expect(
                seat.faceWidth,
                greaterThanOrEqualTo(
                  (seat.isNearRow ? nearFaceMin : backFaceMin) - 1e-9,
                ),
                reason: seat.seatId,
              );
            }
          }

          // Notes: 40×24 with the amount at 15 pt or more.
          for (final note in find.byType(MoneyNote).evaluate()) {
            final size = tester.getSize(find.byWidget(note.widget));
            expect(size.width, greaterThanOrEqualTo(40));
            expect(size.height, greaterThanOrEqualTo(24));
          }
          // The amount, not the blocked note's «؟» (14 on the artboard).
          for (final p in paragraphsIn(tester, find.byKey(MoneyNote.bodyKey))) {
            final size = p.text.style?.fontSize ?? 14;
            expect(p.textScaler.scale(size), greaterThanOrEqualTo(15));
          }

          // Passengers' bubble text: 16, never scaled.
          for (final p in paragraphsIn(
            tester,
            find.descendant(
              of: find.byType(BubblesLayer),
              matching: find.byType(SpeechBubble),
            ),
          )) {
            final style = p.text.style;
            expect(style?.fontSize, 16, reason: p.text.toPlainText());
            expect(p.textScaler.scale(16), 16);
          }
          // بلية's hint (008.5, `Tutorial`): his name at 12, his line at
          // 15 or more.
          for (final p in paragraphsIn(
            tester,
            find.byKey(HintLayer.bubbleKey),
          )) {
            final size = p.textScaler.scale(p.text.style?.fontSize ?? 14);
            expect(
              size,
              greaterThanOrEqualTo(12),
              reason: p.text.toPlainText(),
            );
          }
          for (final p in paragraphsIn(
            tester,
            find.byKey(HintLayer.bubbleKey),
          ).skip(1)) {
            final size = p.textScaler.scale(p.text.style?.fontSize ?? 14);
            expect(
              size,
              greaterThanOrEqualTo(15),
              reason: p.text.toPlainText(),
            );
          }

          // The HUD, strip, dashboard, tags and notes clamp at 1.15.
          final clamped = scale > 1.15 ? 1.15 : scale;
          for (final type in [
            TripHud,
            StationStrip,
            TripDashboard,
            StationTag,
            MoneyNote,
          ]) {
            for (final p in paragraphsIn(tester, find.byType(type))) {
              expect(
                p.textScaler.scale(10),
                closeTo(10 * clamped, 1e-9),
                reason: '$type "${p.text.toPlainText()}"',
              );
            }
          }

          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          for (final span in effectiveFontSizes(tester)) {
            expect(
              span.size,
              greaterThanOrEqualTo(minTextSize),
              reason: '"${span.text}"',
            );
          }

          // Nothing overflows or is cut short, but the HUD's title, which
          // ellipsizes.
          expect(tester.takeException(), isNull);
          final title = find.byKey(TripHud.titleKey);
          final titles = {
            for (final p in paragraphsIn(tester, title)) p.text.toPlainText(),
          };
          for (final p
              in tester.allRenderObjects.whereType<RenderParagraph>()) {
            if (!p.hasSize || p.debugNeedsLayout) continue;
            final text = p.text.toPlainText();
            if (titles.contains(text)) continue;
            expect(p.didExceedMaxLines, isFalse, reason: '"$text" cut short');
          }
          for (final band in [
            find.byType(TripHud),
            find.byType(TripDashboard),
          ]) {
            final boxes = paragraphsIn(tester, band);
            for (var i = 0; i < boxes.length; i++) {
              for (var j = i + 1; j < boxes.length; j++) {
                final a = paragraphRect(boxes[i]);
                final b = paragraphRect(boxes[j]);
                final overlap = a.intersect(b);
                expect(
                  overlap.width > 0.5 && overlap.height > 0.5,
                  isFalse,
                  reason:
                      '"${boxes[i].text.toPlainText()}" $a and '
                      '"${boxes[j].text.toPlainText()}" $b',
                );
              }
            }
          }

          // The bottom third (FR-018, constitution XI 1.4.0). Exempt: the
          // scene's own items, the pause button and internal builds' debug
          // icon, and the cards, which stop play or come before it. Under
          // the threshold the compact dashboard keeps its controls in the
          // bottom 194 pt (M07).
          final scene = definition == null
              ? Rect.zero
              : tester.getRect(find.byType(GameWidget<TripGame>));
          final cards = [
            for (final card in find.byType(AppDialog).evaluate())
              tester.getRect(find.byWidget(card.widget)),
          ];
          for (final node in tappable(tester)) {
            final rect = globalRect(node);
            final label = node.getSemanticsData().label;
            if (label == l10n.tripTopBarPause || label == l10n.tripDebugOpen) {
              continue;
            }
            if (cards.any((card) => card.contains(rect.center))) continue;
            if (scene.contains(rect.topLeft) &&
                scene.contains(rect.bottomRight - const Offset(1, 1))) {
              continue;
            }
            expect(
              rect.top,
              greaterThanOrEqualTo(height * 2 / 3 - 0.5),
              reason: '"$label" at $rect',
            );
          }
          semantics.dispose();
        });
      }
    }
  }

  // بلية's coach under the threshold (compact-trip-layout.md "The coach
  // and the hint in the compact profile"; FR-042): lesson 1 on the
  // tutorial's second trip, when the change is due.
  for (final surface in [TripSurface.small, TripSurface.mid]) {
    for (final scale in textScales) {
      testWidgets('coach · ${surface.name} · ×$scale', (tester) async {
        const tripId = 'line_hay.02';
        await pumpTrip(
          tester,
          tripId: tripId,
          surface: surface,
          textScale: scale,
          economy: await testEconomy(content: tutorialContent()),
          content: contentTestOverrides(assets: tutorialBundledAssets()),
          overrides: [tutorialCoachProvider(tripId).overrideWithValue(1)],
        );
        final c = controllerOf(tester);
        for (var t = 0; t < 120000 && c.model.coach == null; t += 33) {
          c.advance(const Duration(milliseconds: 33));
        }
        expect(c.model.coach, isNotNull, reason: 'no step showed');
        // The anchors report, the layer rebuilds, the hole moves.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final screen = Offset.zero & surface.size;
        bool inside(Rect rect) =>
            rect.left >= screen.left - 0.5 &&
            rect.top >= screen.top - 0.5 &&
            rect.right <= screen.right + 0.5 &&
            rect.bottom <= screen.bottom + 0.5;
        final mark = tester.widget<CoachMark>(find.byType(CoachMark));
        for (final (what, rect) in [
          ('the hole', mark.hole),
          ('بلية', tester.getRect(find.byKey(CoachLayer.headKey))),
          ('the hand', tester.getRect(find.byType(CoachHand))),
          ('the bubble', tester.getRect(find.byKey(CoachLayer.bubbleKey))),
        ]) {
          expect(inside(rect), isTrue, reason: '$what at $rect');
        }
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TripDashboard)),
        );
        final lines = [
          for (final p in paragraphsIn(
            tester,
            find.byKey(CoachLayer.bubbleKey),
          ))
            if (p.text.toPlainText() != l10n.coachName) p,
        ];
        expect(lines, isNotEmpty);
        for (final p in lines) {
          expect(
            p.textScaler.scale(p.text.style?.fontSize ?? 14),
            greaterThanOrEqualTo(15),
            reason: p.text.toPlainText(),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
