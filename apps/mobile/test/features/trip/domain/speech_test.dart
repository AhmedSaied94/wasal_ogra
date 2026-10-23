import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/features/trip/domain/speech.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';

import '../../../helpers/economy.dart';

SpeechResolver resolver(DigitStyle digits, {bool withLine = true}) {
  final content = sampleContent();
  final line = content.line(LineId.lineHay)!;
  return SpeechResolver(
    pool: content.speechPool,
    piasters: NumberFormatter(digits).piasters,
    station: (id) => withLine
        ? line.stations.firstWhere((s) => s.stationId == id).name.arEg
        : 'L',
  );
}

PassengerSpeaks speaks(
  SpeechSlot slot, {
  int variant = 0,
  int? amount,
  String? station,
  String? key,
}) => PassengerSpeaks(
  0,
  passengerId: 'p1',
  slot: slot,
  speechKey: key ?? slot.defaultKey,
  variant: variant,
  amountPiasters: amount,
  stationId: station,
);

void main() {
  test('a line by variant, modulo the pool, with the amount formatted', () {
    final pool = sampleContent().speechPool('passenger.wants_change')!;
    for (final digits in DigitStyle.values) {
      final format = NumberFormatter(digits).piasters;
      for (var variant = 0; variant < 5; variant++) {
        final text = resolver(
          digits,
        ).lineOf(speaks(SpeechSlot.wantsChange, variant: variant, amount: 300));
        final template = pool.lines[variant % pool.lines.length].text.arEg;
        expect(text, template.replaceAll('{amount}', format(300)));
        expect(text, isNot(contains('{amount}')));
      }
    }
  });

  test(
    '{station} is the line station name, or the letter without the line',
    () {
      final content = sampleContent();
      final name = content
          .line(LineId.lineHay)!
          .stations
          .firstWhere((s) => s.stationId == 'madrasa')
          .name
          .arEg;
      final event = speaks(SpeechSlot.stopNear, station: 'madrasa');
      expect(resolver(DigitStyle.western).lineOf(event), contains(name));
      expect(
        resolver(DigitStyle.western, withLine: false).lineOf(event),
        contains('L'),
      );
    },
  );

  test('no pool, no line', () {
    expect(
      resolver(DigitStyle.western)
          .lineOf(speaks(SpeechSlot.thanks, key: 'passenger.nothing_here')),
      isNull,
    );
  });

  test('bubble style by slot', () {
    const expected = {
      BubbleStyle.warning: [
        SpeechSlot.stopNear,
        SpeechSlot.wantsChange,
        SpeechSlot.shortChange,
        SpeechSlot.impatient,
        SpeechSlot.dropMeHere,
        SpeechSlot.changeRequest,
      ],
      BubbleStyle.fight: [
        SpeechSlot.fight,
        SpeechSlot.accused,
        SpeechSlot.dispute,
        SpeechSlot.missedStop,
      ],
      BubbleStyle.thanks: [
        SpeechSlot.thanks,
        SpeechSlot.tip,
        SpeechSlot.returnsExcess,
        SpeechSlot.caught,
      ],
    };
    for (final slot in SpeechSlot.values) {
      final style = expected.entries
          .firstWhere(
            (e) => e.value.contains(slot),
            orElse: () => const MapEntry(BubbleStyle.plain, []),
          )
          .key;
      expect(bubbleStyleOf(slot), style, reason: slot.wire);
    }
  });
}
