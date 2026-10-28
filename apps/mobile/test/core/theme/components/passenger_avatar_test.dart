import 'dart:io' as io;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// A passenger's face in a circle (specs/013-m08-home-result, research R25):
// the result's mistakes and quote, the share picture and the new card.
// `Person` with the look's number, cropped to the head; the look's SVG
// without the file; never an idle loop.

Color? _circle(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(PassengerAvatar),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

void main() {
  test('the four sizes the artboards draw', () {
    expect(
      [for (final s in PassengerAvatarSize.values) s.side],
      [38, 46, 50, 60],
    );
  });

  for (final size in PassengerAvatarSize.values) {
    testWidgets('${size.name}: a ${size.side} pt circle', (tester) async {
      await pumpDesignComponent(
        tester,
        PassengerAvatar(lookId: 'hagga', person: 1, size: size),
      );
      expect(
        tester.getSize(find.byType(PassengerAvatar)),
        Size.square(size.side),
      );
      expect(
        find.descendant(
          of: find.byType(PassengerAvatar),
          matching: find.byType(ClipOval),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('on ground, or on danger.soft for a mistake', (tester) async {
    await pumpDesignComponent(
      tester,
      const PassengerAvatar(
        lookId: 'student',
        person: 5,
        size: PassengerAvatarSize.quote,
      ),
    );
    expect(_circle(tester), ColorTokens.ground);
    await pumpDesignComponent(
      tester,
      const PassengerAvatar(
        lookId: 'student',
        person: 5,
        size: PassengerAvatarSize.mistake,
        mistake: true,
      ),
    );
    expect(_circle(tester), ColorTokens.dangerSoft);
  });

  testWidgets("without the file: the look's SVG", (tester) async {
    await pumpDesignComponent(
      tester,
      const PassengerAvatar(
        lookId: 'headphones',
        person: 6,
        size: PassengerAvatarSize.newCard,
      ),
    );
    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      (svg.bytesLoader as SvgAssetLoader).assetName,
      'assets/illustrations/passengers/headphones.svg',
    );
    expect(find.byType(rive.RiveWidget), findsNothing);
  });

  testWidgets('excluded from semantics: the line beside it names the '
      'passenger', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDesignComponent(
      tester,
      const PassengerAvatar(
        lookId: 'hagga',
        person: 1,
        size: PassengerAvatarSize.quote,
      ),
    );
    expect(
      find.descendant(
        of: find.byType(PassengerAvatar),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('with the file', () {
    late rive.File file;
    late RiveArt art;

    Future<void> load(WidgetTester tester) async {
      await tester.runAsync(() async {
        await rive.RiveNative.init();
        final bytes = io.File(riveArtAsset).readAsBytesSync();
        file = (await rive.File.decode(
          bytes,
          riveFactory: rive.Factory.flutter,
        ))!;
      });
      art = checkRiveArt(file);
      addTearDown(file.dispose);
    }

    testWidgets("Person with the look's number, held still", (tester) async {
      await load(tester);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: RiveArtScope(
            art: art,
            child: const Center(
              child: PassengerAvatar(
                lookId: 'student',
                person: 5,
                size: PassengerAvatarSize.quote,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(rive.RiveWidget), findsOneWidget);
      // No idle loop: its tickers are off.
      expect(
        TickerMode.valuesOf(tester.element(find.byType(rive.RiveWidget)))
            .enabled,
        isFalse,
      );
      final view = tester.widget<RiveArtView>(find.byType(RiveArtView));
      expect(view.artboard, 'Person');
      final artboard = file.artboard('Person')!;
      final model = file
          .defaultArtboardViewModel(artboard)!
          .createDefaultInstance()!;
      view.bind!(model);
      expect(model.number('look')?.value, 5);
      model.dispose();
      artboard.dispose();
      await tester.pumpWidget(const SizedBox());
    }, tags: ['rive']);
  });
}
