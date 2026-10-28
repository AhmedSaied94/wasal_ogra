import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';

// Who talks in a panel (specs/012.5-m22-animated-scenes, data-model.md
// `panelTalkers`): the speaker's Boolean on, the other three off, and all
// four off for anyone without one.

void main() {
  test('each character turns on its own Boolean alone', () {
    for (final talker in sceneTalkers) {
      expect(panelTalkers(talker), {
        for (final t in sceneTalkers) t: t == talker,
      }, reason: talker);
    }
  });

  test('nobody, the narrator and a speaker without a Boolean: all four '
      'off', () {
    for (final nobody in [null, 'narrator', 'bride_father']) {
      expect(panelTalkers(nobody), {
        for (final t in sceneTalkers) t: false,
      }, reason: '$nobody');
    }
  });

  test('always exactly the four Booleans', () {
    expect(sceneTalkers, ['moallem', 'usta', 'belya', 'salma']);
    for (final talker in [...sceneTalkers, null, 'bride_mother']) {
      expect(panelTalkers(talker).keys, unorderedEquals(sceneTalkers));
    }
  });
}
