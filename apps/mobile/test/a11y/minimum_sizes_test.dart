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

/// [iOSTapTargetGuideline], except for a target a scroll view cuts at its
/// edge. The guideline skips those only in a view with implicit scrolling;
/// in any scroll view a cut target is full size once scrolled into view
/// (a line card half past the top of Lines' map). Targets in full view are
/// checked as before.
class UncutTapTargetGuideline extends MinimumTapTargetGuideline {
  UncutTapTargetGuideline(WidgetTester tester)
    : _viewports = [
        for (final e in find.byType(Scrollable).evaluate())
          if (e.renderObject case final RenderBox box? when box.hasSize)
            box.localToGlobal(Offset.zero) & box.size,
      ],
      _ratio = tester.view.devicePixelRatio,
      // As [iOSTapTargetGuideline].
      super(
        size: const Size(44, 44),
        link: 'https://developer.apple.com/design/human-interface-guidelines/ios/visual-design/adaptivity-and-layout/',
      );

  final List<Rect> _viewports;
  final double _ratio;

  /// How near a scroll view's edge a cut target lies, in points.
  static const double _edge = 0.5;

  @override
  bool shouldSkipNode(SemanticsNode node) {
    if (super.shouldSkipNode(node)) return true;
    // The node's rect is already cut to what shows; bring it to the view.
    var rect = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform case final transform?) {
        rect = MatrixUtils.transformRect(transform, rect);
      }
    }
    final target = Rect.fromLTRB(
      rect.left / _ratio,
      rect.top / _ratio,
      rect.right / _ratio,
      rect.bottom / _ratio,
    );
    return _viewports.any(
      (v) =>
          v.inflate(_edge).contains(target.topLeft) &&
          v.inflate(_edge).contains(target.bottomRight) &&
          ((target.top - v.top).abs() < _edge ||
              (v.bottom - target.bottom).abs() < _edge ||
              (target.left - v.left).abs() < _edge ||
              (v.right - target.right).abs() < _edge),
    );
  }
}

/// Checks one state of a screen (T106): every target ≥ 44×44, readable
/// contrast, text ≥ 12 after scaling, nothing overflowing, and no text cut
/// short.
Future<void> expectMinimumSizes(
  WidgetTester tester,
  Set<String> titles,
  Future<void> Function(WidgetTester tester) pump,
) async {
  final semantics = tester.ensureSemantics();
  await pump(tester);
  await expectLater(tester, meetsGuideline(UncutTapTargetGuideline(tester)));
  await expectLater(tester, meetsGuideline(UncutTextContrastGuideline(tester)));
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
