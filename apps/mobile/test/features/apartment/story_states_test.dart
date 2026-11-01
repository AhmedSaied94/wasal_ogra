// The story's boards of 2026-10-31 as behaviour (specs/015-m10-apartment-
// story, T132): the timeline's current card and its done rows' labels, the
// requests sheet's empty card, and Home's card at the end of the story. The
// boxes and the pictures are `test/design/story_states_layout_test.dart` and
// the goldens beside it.
import 'package:content_models/content_models.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/features/apartment/presentation/chapters_page.dart';
import 'package:wassal/features/apartment/presentation/requests_sheet.dart';
import 'package:wassal/features/home/presentation/savings_card.dart';

import '../../design/samples/story_states.dart';
import '../../helpers/lines.dart';

void main() {
  group('the timeline (ChaptersGoal)', () {
    testWidgets('the current goal says the draft\'s line, not its own name', (
      tester,
    ) async {
      await pumpChaptersGoal(tester);
      expect(
        find.descendant(
          of: find.byKey(ChaptersPage.rowKey(ChapterId.ch3Shabka)),
          matching: find.text('الشبكة هي اللي بتفرّح البنت، مش كلام'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the amount alone, in a chip: no bar on the card', (
      tester,
    ) async {
      await pumpChaptersGoal(tester);
      expect(find.textContaining('٢٬٢٠٠'), findsOneWidget);
      expect(find.byType(ProgressBar), findsNothing);
    });

    testWidgets('a done row names its scene: «شوف المشهد: …»', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpChaptersGoal(tester);
      expect(find.bySemanticsLabel('شوف المشهد: أول نظرة'), findsOneWidget);
      expect(find.bySemanticsLabel('شوف المشهد: أبوها بيسأل'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the draft has four chapters; the sample locks three more', (
      tester,
    ) async {
      await pumpChaptersGoal(tester);
      for (final name in ['الصالة', 'المطبخ', 'أوضة النوم', 'الفرح']) {
        expect(find.text(name), findsOneWidget);
      }
    });
  });

  group('the requests sheet (RequestsEmpty)', () {
    testWidgets('a ringed card with the tea tray and one line', (tester) async {
      await pumpRequestsEmpty(tester);
      final card = find.byKey(RequestsSheet.emptyKey);
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            'مفيش طلبات مفتوحة دلوقتي. لو أهل العروسة طلبوا حاجة جديدة، '
            'هتلاقيها هنا.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(SvgPicture)),
        findsOneWidget,
      );
    });
  });

  group('Home at the end of the story (HomeStoryEnd)', () {
    testWidgets('«شقة العُمر» over the end line: no chapter, no bar', (
      tester,
    ) async {
      await pumpHomeStoryEnd(tester);
      final card = find.byType(HomeSavingsCard);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('شقة العُمر')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('باقي الحكاية جاية في تحديث قريب'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('الفصل')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(ProgressBar)),
        findsNothing,
      );
    });

    testWidgets('the card opens the apartment', (tester) async {
      final container = await pumpHomeStoryEnd(tester);
      await tester.tap(find.byType(HomeSavingsCard));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(locationOf(container), '/apartment');
    });
  });
}
