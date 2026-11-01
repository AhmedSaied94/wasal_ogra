// The story viewer's minimum sizes (specs/015-m10-apartment-story SC-006,
// constitution XI, T095): targets ≥ 44×44, text ≥ 12 and bubble text ≥ 15 at
// both scales on the three phones, on the first panel (the skip) and on the
// last (the buttons).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart' show TypeTokens;
import 'package:wassal/features/story/presentation/scene_panel_view.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../design/samples/scene_viewer.dart';
import '../helpers/screens.dart';
import 'minimum_sizes_test.dart'
    show
        UncutTextContrastGuideline,
        clippedText,
        effectiveFontSizes,
        minTextSize;

const _phones = [Size(360, 640), Size(360, 800), Size(390, 844)];

void main() {
  late Set<String> titles;

  setUpAll(() async {
    final l10n = await AppLocalizations.delegate.load(appLocale);
    titles = {for (final d in destinations) d.title(l10n)};
  });

  test('the bubbles\' line is above the bubble minimum', () {
    expect(
      DesignExtras.sceneBubbleLine.fontSize!,
      greaterThanOrEqualTo(TypeTokens.bubbleMinSize),
    );
  });

  for (final size in _phones) {
    for (final scale in textScales) {
      for (final last in [false, true]) {
        testWidgets('SceneViewer · ${last ? 'last' : 'first'} panel · '
            '${size.width.round()}×${size.height.round()} · ×$scale', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          await pumpSceneViewer(
            tester,
            size: size,
            textScale: scale,
            onLastPanel: last,
          );
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
          if (last) {
            for (final i in [0, 1]) {
              expect(
                tester.getSize(find.byKey(ScenePanelView.bubbleKey(i))),
                isNot(Size.zero),
              );
            }
          }
          expect(tester.takeException(), isNull);
          expect(clippedText(tester, titles), isEmpty);
          semantics.dispose();
        });
      }
    }
  }
}
