// The savings card's tap (specs/015-m10-apartment-story, contracts/
// story-flow.md "Changes to merged code", T081, T090): the first waiting
// scene while one waits, else the apartment as before.
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/home/presentation/savings_card.dart';

import '../../helpers/lines.dart';

void main() {
  testWidgets('a waiting scene: the card opens it, and back to Home', (
    tester,
  ) async {
    // «المعلم»'s story trip is finished and its scene not seen: it waits.
    final (container, _) = await pumpLinesApp(
      tester,
      pack: samplePackJsonForLines(),
      location: '/home',
      state: playerState(stars: const {'line_hay.03': 1}),
    );
    await tester.tap(find.byType(HomeSavingsCard));
    await tester.pumpAndSettle();
    final location = Uri.parse(locationOf(container));
    expect(location.path, '/story/scene/the_stand');
    expect(location.queryParameters['then'], '/home');
  });

  testWidgets('no scene waiting: the apartment', (tester) async {
    final (container, _) = await pumpLinesApp(
      tester,
      pack: samplePackJsonForLines(),
      location: '/home',
      state: playerState(
        scenesSeen: const {
          'ch1_first_job': {'opening'},
        },
      ),
    );
    await tester.tap(find.byType(HomeSavingsCard));
    await tester.pumpAndSettle();
    expect(locationOf(container), '/apartment');
  });
}
