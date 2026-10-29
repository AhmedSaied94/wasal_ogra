// What is new on Lines (specs/014-m09-lines-vehicles, research R8).
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/domain/lines_news.dart';

import '../../../helpers/economy.dart';
import '../../../helpers/progress.dart';

void main() {
  test('a new player: nothing but what the start line has', () {
    expect(linesNews(sampleContent(), PlayerProgress.empty, 0), isEmpty);
  });

  test('a line unlocked other than at start', () {
    expect(
      linesNews(sampleContent(), player({}, {microOld}), 0),
      contains('line:line_gamaa'),
    );
  });

  test('a playable story trip without a star', () {
    expect(
      linesNews(sampleContent(), player(hayDone), 0),
      contains('story:line_hay.03'),
    );
    expect(
      linesNews(sampleContent(), player({...hayDone, 'line_hay.03': 1}), 0),
      isNot(contains('story:line_hay.03')),
    );
  });

  test('a vehicle for sale the balance covers', () {
    expect(linesNews(sampleContent(), PlayerProgress.empty, 1500), {
      'vehicle:micro_old',
    });
    expect(linesNews(sampleContent(), PlayerProgress.empty, 1499), isEmpty);
    // Owned: no longer for sale.
    expect(
      linesNews(sampleContent(), player({}, {microOld}), 5000),
      isNot(contains('vehicle:micro_old')),
    );
  });
}
