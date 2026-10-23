import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';

import '../../helpers/trip.dart';

// The screen never says who paid outside a ledger peek (tasks.md T093,
// SC-008, FR-033): every sample trip played through the widgets shows, at
// every pumped frame, no «دافع» or «لسه» badge, and no screen reader label
// that is one of them or ends with one. Speech may say «لسه» in passing;
// a label made of the badge's word is what would tell.

const _badgeWords = ['دافع', 'لسه'];

/// Every semantics label on screen.
List<String> labels(WidgetTester tester) {
  final found = <String>[];
  bool visit(SemanticsNode node) {
    final label = node.getSemanticsData().label;
    if (label.isNotEmpty) found.add(label);
    node.visitChildren(visit);
    return true;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return found;
}

void main() {
  final samples = [
    for (final name in allFixtureNames())
      if (name.startsWith('sample__')) name,
  ];

  test('the five sample trips', () => expect(samples, hasLength(5)));

  for (final name in samples) {
    testWidgets('$name never shows who paid', (tester) async {
      final semantics = tester.ensureSemantics();
      var frames = 0;
      final run = await ScriptedPlayer(
        tester,
        loadFixture(name),
        onFrame: () async {
          frames++;
          expect(find.byType(LedgerBadgeChip), findsNothing);
          for (final word in _badgeWords) {
            expect(find.text(word), findsNothing, reason: 'frame $frames');
          }
          for (final label in labels(tester)) {
            for (final word in _badgeWords) {
              expect(
                label.trim() == word || label.trimRight().endsWith('، $word'),
                isFalse,
                reason: '"$label" at frame $frames',
              );
            }
          }
        },
      ).play();
      expect(run.result, isNotNull);
      expect(frames, greaterThan(100));
      semantics.dispose();
    });
  }
}
