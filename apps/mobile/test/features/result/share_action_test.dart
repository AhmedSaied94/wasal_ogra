// Sharing the result as a picture (specs/013-m08-home-result,
// contracts/result.md "Sharing", US5): a 1080×1080 PNG named after the
// trip with its caption; the card without a quote; Western digits; the
// doubled pay; offline; a second tap ignored; a failure's toast.

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/platform/share_gateway.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/features/result/presentation/share_action.dart';
import 'package:wassal/features/result/presentation/share_card.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../design/samples/result.dart';
import '../../helpers/fake_share_gateway.dart';
import '../../helpers/home.dart';
import '../../helpers/design_component.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/server_status.dart';

const _arabic = NumberFormatter(DigitStyle.arabicIndic);
const _western = NumberFormatter(DigitStyle.western);

/// The picture's side.
const _png = 1080;

/// Lets the share run: the card's frames, then the capture and the
/// encoding, which take real time.
Future<void> _untilShared(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the share never finished');
}

/// [png]'s colour at the card's point [at] (360-point units).
Future<Color> _colorAt(WidgetTester tester, Uint8List png, Offset at) async {
  final pixels = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  const scale = _png / ShareCard.side;
  final x = (at.dx * scale).round();
  final y = (at.dy * scale).round();
  final rgba = pixels!.getUint32((y * _png + x) * 4);
  return Color(((rgba & 0xFF) << 24) | (rgba >> 8));
}

/// [png]'s width and height, from its header.
(int, int) _sizeOf(Uint8List png) {
  final header = ByteData.sublistView(png);
  // The signature (8), the IHDR's length and type (8), then the size.
  return (header.getUint32(16), header.getUint32(20));
}

Future<FakeShareGateway> _result(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
  bool doubled = false,
  bool withQuote = true,
}) async {
  final gateway = FakeShareGateway();
  await pumpResult(
    tester,
    digits: digits,
    slots: false,
    doubled: doubled,
    withQuote: withQuote,
    overrides: [shareGatewayProvider.overrideWithValue(gateway)],
  );
  await tester.ensureVisible(find.byKey(ShareResultButton.buttonKey));
  await tester.pump();
  return gateway;
}

Future<void> _share(WidgetTester tester) async {
  await tester.tap(find.byKey(ShareResultButton.buttonKey));
  await tester.pump();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('a 1080×1080 PNG named after the trip, with the caption', (
    tester,
  ) async {
    final gateway = await _result(tester);
    await _share(tester);
    await _untilShared(tester, () => gateway.shared.isNotEmpty);
    final shared = gateway.shared.single;
    expect(shared.fileName, 'wassal_result_line_gamaa.12.png');
    expect(_sizeOf(shared.png), (_png, _png));
    expect(shared.text, l10n.shareCaption(_arabic.integer(85), 'خط الجامعة'));
    // Where an iPad anchors the sheet: the button.
    expect(
      shared.origin,
      tester.getRect(find.byKey(ShareResultButton.buttonKey)),
    );
    // Drawn, pictures and all: the ground, and the big star's gold.
    expect(
      await _colorAt(tester, shared.png, const Offset(3, 3)),
      ColorTokens.sun,
    );
    expect(
      await _colorAt(tester, shared.png, const Offset(180, 140)),
      ColorTokens.gold,
    );
    expect(currentLocation(tester), '/trip/line_gamaa.12/result');
  });

  testWidgets('Western digits: the caption follows the setting', (
    tester,
  ) async {
    final gateway = await _result(tester, digits: DigitStyle.western);
    await _share(tester);
    await _untilShared(tester, () => gateway.shared.isNotEmpty);
    expect(
      gateway.shared.single.text,
      l10n.shareCaption(_western.integer(85), 'خط الجامعة'),
    );
  });

  testWidgets('the doubled pay', (tester) async {
    final gateway = await _result(tester, doubled: true);
    await _share(tester);
    await _untilShared(tester, () => gateway.shared.isNotEmpty);
    expect(
      gateway.shared.single.text,
      l10n.shareCaption(_arabic.integer(170), 'خط الجامعة'),
    );
  });

  testWidgets('without a quote', (tester) async {
    final gateway = await _result(tester, withQuote: false);
    await _share(tester);
    await _untilShared(tester, () => gateway.shared.isNotEmpty);
    expect(_sizeOf(gateway.shared.single.png), (_png, _png));
  });

  testWidgets('offline: nothing is fetched', (tester) async {
    final gateway = await _result(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(ShareResultButton.buttonKey)),
    );
    (container.read(serverStatusProvider.notifier) as PinnedServerStatus).pin(
      const ServerStatusState(reach: Reach.offline),
    );
    await tester.pump();
    await _share(tester);
    await _untilShared(tester, () => gateway.shared.isNotEmpty);
    expect(_sizeOf(gateway.shared.single.png), (_png, _png));
  });

  testWidgets('a second tap while sharing does nothing', (tester) async {
    final gateway = await _result(tester)
      ..hold();
    await _share(tester);
    await _untilShared(tester, () => gateway.calls == 1);
    await _share(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(gateway.calls, 1);

    gateway.release();
    await tester.pump();
    await _share(tester);
    await _untilShared(tester, () => gateway.calls == 2);
  });

  testWidgets('a failure: the retry toast, and nothing else', (tester) async {
    final gateway = await _result(tester)
      ..failWith = PlatformException(code: 'share');
    await _share(tester);
    await _untilShared(tester, () => gateway.calls == 1);
    await tester.pump();
    expect(find.text(l10n.shareFailed), findsOneWidget);
    expect(find.byType(AppToast), findsOneWidget);
    expect(tester.takeException(), isA<PlatformException>());
    expect(gateway.shared, isEmpty);
    expect(currentLocation(tester), '/trip/line_gamaa.12/result');
  });

  group('the card', () {
    const heading = ResultHeading(
      tripId: 'line_gamaa.12',
      tripIndex: 12,
      lineName: 'خط الجامعة',
      lastStop: 'الجامعة',
      isStory: false,
    );

    Future<void> pumpCard(
      WidgetTester tester,
      ShareSpec spec, {
      DigitStyle digits = DigitStyle.arabicIndic,
    }) => pumpDesignComponent(
      tester,
      ShareCard(spec: spec),
      overrides: [
        numberFormatterProvider.overrideWithValue(NumberFormatter(digits)),
      ],
    );

    testWidgets('no quote card without a quote; the stars in the middle', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const ShareSpec(heading: heading, stars: 2, payJenehat: 85),
      );
      expect(find.byKey(ShareCard.quoteKey), findsNothing);
      final card = tester.getRect(find.byType(ShareCard));
      final stars = tester.getRect(find.byKey(ShareCard.starsKey));
      final title = tester.getRect(find.text('وصلنا الجامعة!'));
      final paid = tester.getRect(find.textContaining('قبضت'));
      expect(stars.center.dx, closeTo(card.center.dx, 1));
      expect(
        stars.center.dy,
        closeTo((title.bottom + paid.top) / 2, ShareCard.side / 20),
      );
    });

    testWidgets('with one: the face, the words and who said them', (
      tester,
    ) async {
      await pumpCard(
        tester,
        ShareSpec(
          heading: heading,
          stars: 2,
          payJenehat: 85,
          quote: (
            look: looks['hagga']!,
            line: 'تسلم يا أسطى',
            labelKey: looks['hagga']!.labelKey,
          ),
        ),
      );
      expect(find.byKey(ShareCard.quoteKey), findsOneWidget);
      expect(find.text(l10n.resultQuote('تسلم يا أسطى')), findsOneWidget);
      expect(find.text('الحاجة'), findsOneWidget);
    });

    testWidgets('Western digits', (tester) async {
      await pumpCard(
        tester,
        const ShareSpec(heading: heading, stars: 3, payJenehat: 170),
        digits: DigitStyle.western,
      );
      expect(shows('قبضت 170'), findsOneWidget);
      expect(shows('المشوار 12 · خط الجامعة'), findsOneWidget);
    });
  });
}
