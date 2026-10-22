import 'package:flame/game.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/sticker_card.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';

import '../helpers/screens.dart';
import '../helpers/trip.dart';
import 'minimum_sizes_test.dart' show effectiveFontSizes;

// The trip screen's minimum sizes (tasks.md T043, contracts/scene-layout.md,
// constitution XI): faces, tokens, bubble text, tap targets, text,
// contrast, labels, and every control outside the scene in the bottom
// third, on the three trip surfaces in the US1–US6 states. M03's suite checks
// touch targets and text at 360×640 (the trip and its pause).

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
          final height = surface.size.height;

          // Faces, from the layout the scene and the overlays share.
          final c = controllerOf(tester);
          final seats = c.session?.facts.definition.seats;
          if (seats != null) {
            final scene = tester.getRect(find.byType(GameWidget<TripGame>));
            expect(scene.height, greaterThanOrEqualTo(compliantSceneHeight));
            final layout = SceneLayout(
              seats,
              width: scene.width,
              height: scene.height,
            );
            for (final seat in layout.seats.values) {
              expect(
                seat.face.width,
                greaterThanOrEqualTo(
                  seat.isNearRow ? nearFaceMin : backFaceMin,
                ),
                reason: seat.seatId,
              );
            }
          }

          // Money tokens: 40×24 with the amount at 15 pt.
          for (final chip in find.byType(TokenChip).evaluate()) {
            final size = tester.getSize(find.byWidget(chip.widget));
            expect(size.width, greaterThanOrEqualTo(tokenMinWidth));
            expect(size.height, greaterThanOrEqualTo(tokenMinHeight));
          }
          for (final p
              in tester.allRenderObjects.whereType<RenderParagraph>()) {
            final inBubble = find
                .ancestor(
                  of: find.byWidgetPredicate(
                    (w) => w is RichText && w.text == p.text,
                  ),
                  matching: find.byType(Bubble),
                )
                .evaluate()
                .isNotEmpty;
            if (inBubble) {
              final size = p.text.style?.fontSize ?? 14;
              expect(p.textScaler.scale(size), greaterThanOrEqualTo(15));
            }
          }

          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          for (final span in effectiveFontSizes(tester)) {
            expect(
              span.size,
              greaterThanOrEqualTo(TypeTokens.minFontSize),
              reason: '"${span.text}"',
            );
          }

          // The bottom third (FR-018, constitution XI 1.4.0). Exempt: the
          // scene's own items, the pause button and internal builds' debug
          // icon, and the cards, which stop play or come before it.
          final scene = seats == null
              ? Rect.zero
              : tester.getRect(find.byType(GameWidget<TripGame>));
          final cards = [
            for (final card in find.byType(StickerCard).evaluate())
              tester.getRect(find.byWidget(card.widget)),
          ];
          for (final node in tappable(tester)) {
            final rect = globalRect(node);
            final label = node.getSemanticsData().label;
            if (label == 'إيقاف' || label == 'لوحة التجربة') continue;
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
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      }
    }
  }
}
