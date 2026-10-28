// Home's street (specs/013-m08-home-result, FR-004, research R13): the
// sign and the caller per vehicle, the bubble's re-pop on a fake clock,
// reduced motion, and nothing to tap or drawn as canvas text.
import 'dart:io';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/components/bubble_pop.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/features/home/presentation/street_scene.dart';
import 'package:wassal/features/trip/domain/looks.dart';

import '../../helpers/design_component.dart';

const _size = Size(358, 332);

Future<void> _pump(
  WidgetTester tester,
  VehicleId vehicle, {
  String? sign = 'الجامعة',
  String? station = 'الجامعة',
}) => pumpDesignComponent(
  tester,
  SizedBox.fromSize(
    size: _size,
    child: StreetScene(vehicle: vehicle, sign: sign, station: station),
  ),
);

String _svgOf(SvgPicture picture) =>
    (picture.bytesLoader as SvgAssetLoader).assetName;

/// The callers' SVGs: the barker's and بلية's, not the riders' faces.
Iterable<String> _callers(WidgetTester tester) => [
  for (final element in find.byType(SvgPicture).evaluate())
    if (element.findAncestorWidgetOfExactType<PassengerAvatar>() == null)
      if (_svgOf(element.widget as SvgPicture) case final path
          when path == looks['regular']!.svg ||
              path == CharacterAvatar.path('belya'))
        path,
];

void main() {
  testWidgets('the microbus: its roof sign, and the barker calling', (
    tester,
  ) async {
    await _pump(tester, VehicleId.microOld);
    expect(find.byKey(StreetScene.signKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(StreetScene.signKey),
        matching: find.text('الجامعة'),
      ),
      findsOneWidget,
    );
    expect(find.text('الجامعة.. الجامعة!'), findsOneWidget);
    // The barker is a regular-looking passenger at the door.
    expect(_callers(tester), [looks['regular']!.svg]);
  });

  testWidgets('the tuktuk: no sign, and بلية calls instead', (tester) async {
    await _pump(tester, VehicleId.tuktuk, sign: null, station: 'الحي');
    expect(find.byKey(StreetScene.signKey), findsNothing);
    expect(find.text('الحي.. الحي!'), findsOneWidget);
    expect(_callers(tester), [CharacterAvatar.path('belya')]);
  });

  testWidgets('two riders: regular and hagga', (tester) async {
    await _pump(tester, VehicleId.microOld);
    expect(
      [
        for (final a in tester.widgetList<PassengerAvatar>(
          find.byType(PassengerAvatar),
        ))
          a.lookId,
      ],
      ['regular', 'hagga'],
    );
  });

  testWidgets('the bubble pops on entering and every barkerRepop', (
    tester,
  ) async {
    await _pump(tester, VehicleId.microOld);
    Key? pop() => tester
        .widget<KeyedSubtree>(
          find
              .ancestor(
                of: find.byKey(StreetScene.bubbleKey),
                matching: find.byType(KeyedSubtree),
              )
              .first,
        )
        .key;
    final first = pop();
    await tester.pump(DesignExtras.barkerRepop - const Duration(seconds: 1));
    expect(pop(), first);
    await tester.pump(const Duration(seconds: 1));
    final second = pop();
    expect(second, isNot(first));
    await tester.pump(DesignExtras.barkerRepop);
    expect(pop(), isNot(second));
    // The pop is a scale from the bottom, still running.
    expect(
      find.descendant(
        of: find.byType(BubblePop),
        matching: find.byType(Transform),
      ),
      findsWidgets,
    );
  });

  testWidgets('reduced motion: no pop, no re-pop', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, VehicleId.microOld);
    Key? pop() => tester
        .widget<KeyedSubtree>(
          find
              .ancestor(
                of: find.byKey(StreetScene.bubbleKey),
                matching: find.byType(KeyedSubtree),
              )
              .first,
        )
        .key;
    final first = pop();
    await tester.pump(DesignExtras.barkerRepop * 2);
    expect(pop(), first);
    expect(
      find.descendant(
        of: find.byType(BubblePop),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
    // The vehicle and the people hold their static art (Rive's idle loops
    // stop under reduced motion).
    expect(find.byType(SvgPicture), findsWidgets);
  });

  testWidgets('nothing to tap; the text is Flutter text', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, VehicleId.microOld);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    // The call is read; the sign and the art aren't.
    expect(find.bySemanticsLabel('الجامعة.. الجامعة!'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('a taller card shows more sky: the street keeps to the '
      'bottom', (tester) async {
    double signFromTop() =>
        tester.getRect(find.byKey(StreetScene.signKey)).top -
        tester.getRect(find.byType(StreetScene)).top;
    await _pump(tester, VehicleId.microOld);
    final short = signFromTop();
    await pumpDesignComponent(
      tester,
      const SizedBox(
        width: 358,
        height: 432,
        child: StreetScene(
          vehicle: VehicleId.microOld,
          sign: 'الجامعة',
          station: 'الجامعة',
        ),
      ),
    );
    expect(signFromTop() - short, closeTo(100, 0.5));
  });

  testWidgets("the bubble keeps inside the card, and below the daily row's "
      'band', (tester) async {
    Rect bubble() => tester.getRect(find.byKey(StreetScene.bubbleKey));
    Future<void> pump({double clearTop = 0}) => pumpDesignComponent(
      tester,
      SizedBox(
        width: 358,
        height: 232,
        child: StreetScene(
          vehicle: VehicleId.microOld,
          sign: 'الجامعة',
          station: 'مستشفى الجامعة الجديدة',
          clearTop: clearTop,
        ),
      ),
    );
    await pump();
    final scene = tester.getRect(find.byType(StreetScene));
    // A long name: the body moves aside rather than leave the card.
    expect(bubble().right, lessThanOrEqualTo(scene.right - 8));
    expect(bubble().left, greaterThanOrEqualTo(scene.left + 8));
    final free = bubble().top - scene.top;
    await pump(clearTop: free + 30);
    expect(bubble().top - scene.top, closeTo(free + 30, 0.5));
  });

  for (final (vehicle, file) in [
    (VehicleId.microOld, 'microbus_old'),
    (VehicleId.tuktuk, 'tuktuk'),
  ]) {
    testWidgets("the $file's static art: the vehicle alone, without its "
        "card's sky, kerb and sun", (tester) async {
      await _pump(tester, vehicle);
      final loader = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .map((p) => p.bytesLoader)
          .whereType<SvgAssetLoader>()
          .singleWhere((l) => l.assetName.endsWith('vehicles/$file.svg'));
      final bytes = File(loader.assetName).readAsBytesSync();
      final svg = loader.provideSvg(ByteData.sublistView(bytes));
      expect(RegExp('^<svg[^>]*><g[ >]').hasMatch(svg), isTrue);
      expect(svg.length, lessThan(bytes.length));
    });
  }
}
