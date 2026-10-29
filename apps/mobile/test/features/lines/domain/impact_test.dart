// The impact line (specs/014-m09-lines-vehicles, research R7, FR-032).
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/progress/domain/player_progress.dart';
import 'package:wassal/features/lines/domain/impact.dart';

import '../../../helpers/progress.dart';

String _t(String line, int n) => '$line.${n.toString().padLeft(2, '0')}';

Map<String, int> get _hayRegular => {
  for (var n = 1; n <= 19; n++) _t('line_hay', n): 1,
};

void main() {
  test('the microbus in ch2 names the shabka and what it still lacks', () {
    // draftShaped: the micro_old 3,200, the shabka 6,000.
    final p = player(_hayRegular);
    expect(
      impactAfterPurchase(draftContent(), p, 4000, VehicleId.microOld),
      const Impact(goalName: 'الشبكة', amount: 6000 - (4000 - 3200)),
    );
  });

  test('an apartment piece', () {
    // The sample: ch3 is owned, so ch4's salon is the goal; its first
    // piece by order is the sitara or the nish.
    final c = sampleWith((json) {
      for (final price in entries(
        json['catalog']! as Map<String, Object?>,
        'prices',
      )) {
        if (price['sku_id'] == 'micro_old') price['amount'] = 100;
      }
    });
    final p = player(hayDone, {shabka});
    final impact = impactAfterPurchase(c, p, 300, VehicleId.microOld);
    expect(impact, isNotNull);
    expect(impact!.amount, greaterThan(0));
    expect(impact.goalName, isNotEmpty);
  });

  test('a line goal has no price: hidden', () {
    // A new player's ch1 goal is to finish line_hay.
    final c = sampleWith((json) {
      final chapters = entries(json, 'chapters');
      final ch2 = chapters.firstWhere(
        (ch) => ch['chapter_id'] == 'ch2_her_father',
      );
      ch2['goal'] = {'kind': 'complete_line', 'line_id': 'line_gamaa'};
    });
    expect(
      impactAfterPurchase(c, player(hayDone), 5000, VehicleId.microOld),
      isNull,
    );
  });

  test('no target: hidden', () {
    final c = sampleWith((json) => json['chapters'] = <Object?>[]);
    expect(
      impactAfterPurchase(c, PlayerProgress.empty, 5000, VehicleId.microOld),
      isNull,
    );
  });

  test('nothing missing: hidden', () {
    final p = player(_hayRegular);
    expect(
      impactAfterPurchase(draftContent(), p, 9200, VehicleId.microOld),
      isNull,
    );
    expect(
      impactAfterPurchase(draftContent(), p, 10000, VehicleId.microOld),
      isNull,
    );
  });

  test('not affordable, or not for sale: hidden', () {
    final p = player(_hayRegular);
    expect(
      impactAfterPurchase(draftContent(), p, 3000, VehicleId.microOld),
      isNull,
    );
    expect(
      impactAfterPurchase(draftContent(), p, 9000, VehicleId.tuktuk),
      isNull,
    );
  });
}
