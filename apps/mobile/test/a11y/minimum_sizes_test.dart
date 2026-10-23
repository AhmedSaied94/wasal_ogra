import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Scrollable;
import 'package:wassal/bootstrap/app.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../helpers/surfaces.dart';

// Minimum sizes and contrast as acceptance criteria (FR-041, SC-004,
// constitution XI): touch targets ≥ 44×44, text ≥ 12, WCAG AA, no overflow,
// and no text cut short except a screen or sheet title, which ellipsizes
// (specs/008.5-m21-design-refresh SC-004).

/// Any text, anywhere (ux-spec minimum sizes).
const minTextSize = 12.0;

/// Every span's font size after text scaling, across all painted text.
Iterable<({String text, double size})> effectiveFontSizes(
  WidgetTester tester,
) sync* {
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    final spans = <({String text, double size})>[];
    void visit(InlineSpan span, double inherited) {
      final size = span.style?.fontSize ?? inherited;
      if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false)) {
        spans.add((text: span.text!, size: paragraph.textScaler.scale(size)));
      }
      if (span is TextSpan) {
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, size);
        }
      }
    }

    // 14 is the engine default when no size is set anywhere.
    visit(paragraph.text, 14);
    yield* spans;
  }
}

/// The text of every laid-out paragraph that ran out of lines, except
/// titles. A page under another one may never have been laid out.
List<String> clippedText(WidgetTester tester, Set<String> titles) => [
  for (final paragraph in tester.allRenderObjects.whereType<RenderParagraph>())
    if (paragraph.hasSize &&
        !paragraph.debugNeedsLayout &&
        paragraph.didExceedMaxLines &&
        !titles.contains(paragraph.text.toPlainText()))
      paragraph.text.toPlainText(),
];

/// [textContrastGuideline], except for text a scroll view cuts at its edge.
/// The guideline samples a text's whole box, so for cut text it reads
/// whatever lies past the edge (the bottom nav and its lip) as the text's
/// background. Text in full view is checked as before.
class UncutTextContrastGuideline extends MinimumTextContrastGuideline {
  UncutTextContrastGuideline(WidgetTester tester)
    : _viewports = [
        for (final e in find.byType(Scrollable).evaluate())
          if (e.renderObject case final RenderBox box? when box.hasSize)
            box.localToGlobal(Offset.zero) & box.size,
      ];

  final List<Rect> _viewports;

  @override
  bool isNodeOffScreen(Rect paintBounds, ui.FlutterView window) {
    // The guideline passes the text's box inflated by 4.
    final text = paintBounds.deflate(4);
    return super.isNodeOffScreen(paintBounds, window) ||
        _viewports.any((v) => v.overlaps(text) && v.intersect(text) != text);
  }
}

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  for (final screen in [...shellScreens(), ...navigationScreens()]) {
    for (final surface in Surface.values) {
      for (final scale in textScales) {
        for (final digits in DigitStyle.values) {
          testWidgets(
            '${screen.name} · ${surface.name} · ×$scale · ${digits.name}',
            (tester) async {
              final semantics = tester.ensureSemantics();
              await pumpWassalApp(
                tester,
                overrides: screen.overrides,
                initialLocation: screen.location,
                surface: surface,
                textScale: scale,
                digits: digits,
              );
              await screen.then?.call(tester);

              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(
                tester,
                meetsGuideline(UncutTextContrastGuideline(tester)),
              );
              for (final span in effectiveFontSizes(tester)) {
                expect(
                  span.size,
                  greaterThanOrEqualTo(minTextSize),
                  reason: '"${span.text}"',
                );
              }
              expect(tester.takeException(), isNull);
              expect(clippedText(tester, titles), isEmpty);
              semantics.dispose();
            },
          );
        }
      }
    }
  }
}
