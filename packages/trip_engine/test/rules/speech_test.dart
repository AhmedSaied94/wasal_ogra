// Speech (rules.md §12): the key, the variant and the placeholders.
import 'package:test/test.dart';
import 'package:trip_engine/trip_engine.dart';

import '../support/builders.dart';
import '../support/scripts.dart';

TripEngine _trip({int seed = 1, Map<String, String>? speechKeys}) => startTrip(
  (TripBuilder()
        ..seed(seed)
        ..station('kobri', 10)
        ..station('gamaa', 20)
        ..passenger(
          'p1',
          seat: 'A_r',
          dest: 'kobri',
          payment: [1000],
          paysAt: 0,
          speechKeys: speechKeys,
        )
        ..passenger(
          'p2',
          seat: 'A_m',
          dest: 'gamaa',
          board: 'kobri',
          payment: [1000],
        ))
      .build(),
);

void main() {
  test(
    'the key is passenger.<slot>, unless the passenger overrides the slot',
    () {
      final plain = eventsOf<PassengerSpeaks>(_trip().step()).single;
      expect(plain.speechKey, 'passenger.pays');
      final custom = eventsOf<PassengerSpeaks>(
        _trip(speechKeys: {'pays': 'passenger.pays_loud'}).step(),
      ).single;
      expect(custom.speechKey, 'passenger.pays_loud');
      expect(custom.slot, SpeechSlot.pays);
    },
  );

  test('the variant is the next PRNG value, in emission order', () {
    final engine = _trip();
    final speeches = eventsOf<PassengerSpeaks>(engine.stepToSeconds(20));
    expect(speeches.take(2).map((s) => s.variant), [270369, 67634689]);
    expect(engine.state.prng, isNot(1));
  });

  test('placeholders are present only where the slot declares them', () {
    final speeches = eventsOf<PassengerSpeaks>(_trip().stepToSeconds(20));
    final pays = speeches.firstWhere((s) => s.slot == SpeechSlot.pays);
    expect((pays.amountPiasters, pays.stationId), (1000, null));
    final stop = speeches.firstWhere((s) => s.slot == SpeechSlot.stopNear);
    expect((stop.amountPiasters, stop.stationId), (null, 'kobri'));
    final boards = speeches.firstWhere((s) => s.slot == SpeechSlot.boards);
    expect((boards.amountPiasters, boards.stationId), (null, null));
  });

  test('speech changes no other state', () {
    final one = _trip(seed: 1);
    final two = _trip(seed: 2);
    final eventsOne = one.stepToSeconds(20);
    final eventsTwo = two.stepToSeconds(20);
    Map<String, Object> withoutPrng(TripEngine engine) =>
        engine.state.toJson()..remove('prng');
    expect(withoutPrng(one), withoutPrng(two));
    Map<String, Object> withoutVariant(DomainEvent event) =>
        event.toJson()..remove('variant');
    expect(
      eventsOne.map(withoutVariant).toList(),
      eventsTwo.map(withoutVariant).toList(),
    );
  });
}
