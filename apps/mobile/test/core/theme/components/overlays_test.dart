import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// Sheets, dialogs, banners and toasts (HANDOFF §3.3, §6.5; research R5).

const _open = Key('open');

/// A button that runs [show] with a context under the navigator.
Widget _opener(void Function(BuildContext context) show) => Builder(
  builder: (context) => GestureDetector(
    key: _open,
    behavior: HitTestBehavior.opaque,
    onTap: () => show(context),
    child: const SizedBox(width: 120, height: 60),
  ),
);

Future<void> _openSheet(WidgetTester tester, {bool reduced = false}) async {
  await pumpDesignComponent(
    tester,
    _opener(
      (context) => showAppSheet<void>(
        context: context,
        title: 'عنوان اللوح',
        builder: (_) => const SizedBox(height: 300, child: Text('جوه اللوح')),
      ),
    ),
    reducedMotion: reduced,
  );
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
  expect(find.text('جوه اللوح'), findsOne);
}

Future<void> _openDialog(
  WidgetTester tester, {
  bool barrierDismissible = true,
  bool reduced = false,
}) async {
  await pumpDesignComponent(
    tester,
    _opener(
      (context) => showAppDialog<void>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (context) => AppDialog(
          child: AppButton.primary(
            label: 'أيوه',
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
    reducedMotion: reduced,
  );
  await tester.tap(find.byKey(_open));
}

void main() {
  group('AppSheet', () {
    testWidgets('the frame: grabber, title, close; white with the 28 top '
        'radius', (tester) async {
      await _openSheet(tester);
      expect(find.text('عنوان اللوح'), findsOne);
      expect(find.byType(IconCircleButton), findsOne);
      expect(
        tester.getSize(find.byKey(AppSheet.grabberKey)),
        const Size(44, 5),
      );
    });

    testWidgets('a drag of more than 25% dismisses it', (tester) async {
      await _openSheet(tester);
      final height = tester.getSize(find.byType(AppSheet)).height;
      await tester.drag(find.byType(AppSheet), Offset(0, height * 0.4));
      await tester.pumpAndSettle();
      expect(find.text('جوه اللوح'), findsNothing);
    });

    testWidgets('a drag of less does not', (tester) async {
      await _openSheet(tester);
      final height = tester.getSize(find.byType(AppSheet)).height;
      await tester.timedDrag(
        find.byType(AppSheet),
        Offset(0, height * 0.15),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('جوه اللوح'), findsOne);
    });

    testWidgets('a fling dismisses it', (tester) async {
      await _openSheet(tester);
      await tester.fling(find.byType(AppSheet), const Offset(0, 60), 1500);
      await tester.pumpAndSettle();
      expect(find.text('جوه اللوح'), findsNothing);
    });

    testWidgets('✕ dismisses it', (tester) async {
      await _openSheet(tester);
      await tester.tap(find.byType(IconCircleButton));
      await tester.pumpAndSettle();
      expect(find.text('جوه اللوح'), findsNothing);
    });

    testWidgets('system back dismisses it', (tester) async {
      await _openSheet(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('جوه اللوح'), findsNothing);
    });

    testWidgets('the scrim dismisses it', (tester) async {
      await _openSheet(tester);
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.text('جوه اللوح'), findsNothing);
    });

    testWidgets('in over 280 ms, out over 200 ms', (tester) async {
      await pumpDesignComponent(
        tester,
        _opener(
          (context) => showAppSheet<void>(
            context: context,
            title: 't',
            builder: (_) => const SizedBox(height: 200),
          ),
        ),
      );
      await tester.tap(find.byKey(_open));
      await tester.pump();
      await tester.pump(
        MotionTokens.sheetIn - const Duration(milliseconds: 20),
      );
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.tap(find.byType(IconCircleButton));
      await tester.pump();
      await tester.pump(
        MotionTokens.sheetOut - const Duration(milliseconds: 20),
      );
      expect(find.byType(AppSheet), findsOne);
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(AppSheet), findsNothing);
    });

    testWidgets('reduced motion: no slide, a fade of at most 150 ms', (
      tester,
    ) async {
      await _openSheet(tester, reduced: true);
      await tester.tap(find.byType(IconCircleButton));
      await tester.pump();
      await tester.pump(DesignExtras.reducedFade);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(AppSheet), findsNothing);
    });
  });

  group('AppDialog', () {
    testWidgets('scales 0.92 → 1 over 220 ms', (tester) async {
      await _openDialog(tester);
      await tester.pump();
      final first = tester.widget<ScaleTransition>(
        find.ancestor(
          of: find.byType(AppDialog),
          matching: find.byType(ScaleTransition),
        ),
      );
      expect(first.scale.value, closeTo(0.92, 0.01));
      await tester.pump(MotionTokens.dialogIn);
      expect(first.scale.value, closeTo(1, 0.001));
    });

    testWidgets('the card: paper, radius 26', (tester) async {
      await _openDialog(tester);
      await tester.pumpAndSettle();
      final face = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AppDialog),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final d = face.decoration as BoxDecoration;
      expect(d.color, ColorTokens.paper);
      expect(d.borderRadius, BorderRadius.circular(DesignExtras.dialogRadius));
    });

    testWidgets('dismissible: the scrim closes it', (tester) async {
      await _openDialog(tester);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('not dismissible: the scrim and back do nothing', (
      tester,
    ) async {
      await _openDialog(tester, barrierDismissible: false);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOne);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOne);
      await tester.tap(find.text('أيوه'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('reduced motion: no scale', (tester) async {
      await _openDialog(tester, reduced: true);
      await tester.pump();
      expect(
        find.ancestor(
          of: find.byType(AppDialog),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
    });
  });

  group('EventBanner', () {
    testWidgets('announced once; hides itself after 4 s', (tester) async {
      final announced = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler(
        SystemChannels.accessibility,
        (message) async {
          announced.add(message);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler(SystemChannels.accessibility, null),
      );
      var hidden = 0;
      await pumpDesignComponent(
        tester,
        SizedBox(
          width: 358,
          child: EventBanner(
            title: 'الأجرة زادت!',
            subtitle: 'المستشفى بقت ٨ بدل ٧',
            onHidden: () => hidden++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('الأجرة زادت!'), findsOne);
      await tester.pump(const Duration(seconds: 2));
      expect(hidden, 0);
      await tester.pump(DesignExtras.bannerHold);
      await tester.pumpAndSettle();
      expect(hidden, 1);
      final announcements = announced.whereType<Map<Object?, Object?>>().where(
        (m) => m['type'] == 'announce',
      );
      expect(announcements, hasLength(1));
      expect(
        (announcements.single['data']! as Map<Object?, Object?>)['message'],
        contains('الأجرة زادت!'),
      );
    });

    testWidgets('the look: danger, h 54, radius 18, ink text', (tester) async {
      await pumpDesignComponent(
        tester,
        const SizedBox(
          width: 358,
          child: EventBanner(title: 'الأجرة زادت!', hideAfter: null),
        ),
      );
      await tester.pump();
      final banner = find.byType(EventBanner);
      expect(tester.getSize(banner).height, 54);
      expect(
        tester.widget<Text>(find.text('الأجرة زادت!')).style!.color,
        ColorTokens.ink,
      );
    });
  });

  testWidgets('UndoToast: counts its seconds down, then goes after 3 s', (
    tester,
  ) async {
    var undone = 0;
    var gone = 0;
    await pumpDesignComponent(
      tester,
      SizedBox(
        width: 358,
        child: UndoToast(
          message: 'اتشرى كيس فكة بـ١٠ بون',
          seconds: (n) => '$n',
          onUndo: () => undone++,
          onExpired: () => gone++,
        ),
      ),
    );
    expect(find.text('رجّع 3'), findsOne);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('رجّع 2'), findsOne);
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(undone, 1);
    await tester.pump(MotionTokens.toastHold);
    expect(gone, 0, reason: 'an undone toast does not expire');
  });

  testWidgets('UndoToast: unused, it expires after 3 s', (tester) async {
    var gone = 0;
    await pumpDesignComponent(
      tester,
      SizedBox(
        width: 358,
        child: UndoToast(
          message: 'اتشرى',
          seconds: (n) => '$n',
          onUndo: () {},
          onExpired: () => gone++,
        ),
      ),
    );
    await tester.pump(MotionTokens.toastHold);
    await tester.pump();
    expect(gone, 1);
  });

  testWidgets('AppToast: a message with no action, gone after its hold', (
    tester,
  ) async {
    await pumpDesignComponent(
      tester,
      _opener((context) => showAppToast(context, 'دوس رجوع تاني')),
    );
    await tester.tap(find.byKey(_open));
    await tester.pump();
    await tester.pump(MotionTokens.toast);
    expect(find.text('دوس رجوع تاني'), findsOne);
    expect(
      find.descendant(
        of: find.byType(AppToast),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
    await tester.pump(MotionTokens.toastHold);
    await tester.pumpAndSettle();
    expect(find.text('دوس رجوع تاني'), findsNothing);
  });

  testWidgets('OfflineBanner, InlineAlert and StatusCard draw', (tester) async {
    var retried = 0;
    await pumpDesignComponent(
      tester,
      SizedBox(
        width: 358,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            const OfflineBanner(message: 'انت أوفلاين'),
            InlineAlert(
              message: 'الإعلان مش جاهز دلوقتي',
              icon: 'ad_screen',
              action: 'بـ٨ بونات',
              onAction: () => retried++,
            ),
            StatusCard.error(
              title: 'الدفع ما تمّش',
              message: 'وما اتخصمش منك حاجة.',
              actions: [
                AppButton.primary(
                  label: 'جرّب تاني',
                  size: AppButtonSize.compact,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(OfflineBanner)).height,
      greaterThanOrEqualTo(40),
    );
    await tester.tap(find.text('بـ٨ بونات'));
    await tester.pumpAndSettle();
    expect(retried, 1);
    expect(find.text('الدفع ما تمّش'), findsOne);
  });
}
