import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/typography.dart';

import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../helpers/surfaces.dart';

// Minimum sizes and contrast as acceptance criteria (FR-041, SC-004,
// constitution XI): touch targets ≥ 44×44, text ≥ 12, WCAG AA, no overflow.

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

void main() {
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
              await expectLater(tester, meetsGuideline(textContrastGuideline));
              for (final span in effectiveFontSizes(tester)) {
                expect(
                  span.size,
                  greaterThanOrEqualTo(TypeTokens.minFontSize),
                  reason: '"${span.text}"',
                );
              }
              expect(tester.takeException(), isNull);
              semantics.dispose();
            },
          );
        }
      }
    }
  }
}
