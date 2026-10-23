import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';

// Controls (HANDOFF §3.3; contracts/components.md).

class _SwitchHost extends StatefulWidget {
  const _SwitchHost({this.enabled = true, this.initial = false});

  final bool enabled;
  final bool initial;

  @override
  State<_SwitchHost> createState() => _SwitchHostState();
}

class _SwitchHostState extends State<_SwitchHost> {
  late bool on = widget.initial;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 253,
    child: AppSwitch(
      label: 'الصوت',
      value: on,
      enabled: widget.enabled,
      onChanged: (v) => setState(() => on = v),
    ),
  );
}

Color? _trackColor(WidgetTester tester) =>
    (tester
                .widget<AnimatedContainer>(find.byKey(AppSwitch.trackKey))
                .decoration!
            as BoxDecoration)
        .color;

void main() {
  group('AppSwitch', () {
    testWidgets('off: ground.lip track, knob at the start (right in RTL)', (
      tester,
    ) async {
      await pumpDesignComponent(tester, const _SwitchHost());
      expect(_trackColor(tester), ColorTokens.groundLip);
      final track = tester.getRect(find.byKey(AppSwitch.trackKey));
      final knob = tester.getRect(find.byKey(AppSwitch.knobKey));
      expect(track.size, const Size(52, 30));
      expect(knob.size, const Size(24, 24));
      expect(knob.right, closeTo(track.right - 3, 0.5));
    });

    testWidgets('a tap anywhere on the row turns it on: primary, knob at the '
        'end (left in RTL)', (tester) async {
      await pumpDesignComponent(tester, const _SwitchHost());
      // Tap the label, far from the track.
      await tester.tap(find.text('الصوت'));
      await tester.pumpAndSettle();
      expect(_trackColor(tester), ColorTokens.primary);
      final track = tester.getRect(find.byKey(AppSwitch.trackKey));
      final knob = tester.getRect(find.byKey(AppSwitch.knobKey));
      expect(knob.left, closeTo(track.left + 3, 0.5));
    });

    testWidgets('the row: white, 52 high, radius 16', (tester) async {
      await pumpDesignComponent(tester, const _SwitchHost());
      final row = tester.getSize(find.byType(AppSwitch));
      expect(row.height, 52);
    });

    testWidgets('disabled: no toggle, read as disabled', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDesignComponent(tester, const _SwitchHost(enabled: false));
      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      expect(_trackColor(tester), ColorTokens.groundLip);
      final node = tester.getSemantics(find.byType(AppSwitch));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    });

    testWidgets('a screen reader hears the label and the state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpDesignComponent(tester, const _SwitchHost(initial: true));
      final node = tester.getSemantics(find.byType(AppSwitch));
      expect(node.label, 'الصوت');
      expect(node.flagsCollection.isToggled, Tristate.isTrue);
      semantics.dispose();
    });
  });

  group('Segmented', () {
    Widget segmented(SegmentedStyle style, ValueChanged<int> onChanged) =>
        SizedBox(
          width: 253,
          child: Segmented<int>(
            style: style,
            value: 0,
            segments: const [(0, 'الصالة'), (1, 'المطبخ')],
            onChanged: onChanged,
          ),
        );

    Color? fillOf(WidgetTester tester, String label) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    testWidgets('sun style: the active segment sun with ink 700', (
      tester,
    ) async {
      await pumpDesignComponent(tester, segmented(SegmentedStyle.sun, (_) {}));
      expect(fillOf(tester, 'الصالة'), ColorTokens.sun);
      final active = tester.widget<Text>(find.text('الصالة')).style!;
      expect(active.color, ColorTokens.ink);
      expect(active.fontWeight, FontWeight.w700);
      final idle = tester.widget<Text>(find.text('المطبخ')).style!;
      expect(idle.color, ColorTokens.ink2);
      expect(idle.fontWeight, FontWeight.w600);
      expect(tester.getSize(find.byType(Segmented<int>)).height, 52);
    });

    testWidgets('primary style: the active segment primary with white', (
      tester,
    ) async {
      await pumpDesignComponent(
        tester,
        segmented(SegmentedStyle.primary, (_) {}),
      );
      expect(fillOf(tester, 'الصالة'), ColorTokens.primary);
      expect(
        tester.widget<Text>(find.text('الصالة')).style!.color,
        ColorTokens.paper,
      );
    });

    testWidgets('a tap picks a segment; the chosen one reads as selected', (
      tester,
    ) async {
      int? picked;
      final semantics = tester.ensureSemantics();
      await pumpDesignComponent(
        tester,
        segmented(SegmentedStyle.primary, (v) => picked = v),
      );
      await tester.tap(find.text('المطبخ'));
      await tester.pumpAndSettle();
      expect(picked, 1);
      final node = tester.getSemantics(
        find
            .ancestor(of: find.text('الصالة'), matching: find.byType(Semantics))
            .first,
      );
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      semantics.dispose();
    });

    testWidgets('four segments share the width', (tester) async {
      await pumpDesignComponent(
        tester,
        SizedBox(
          width: 300,
          child: Segmented<int>(
            value: 2,
            segments: const [(0, 'أ'), (1, 'ب'), (2, 'ج'), (3, 'د')],
            onChanged: (_) {},
          ),
        ),
      );
      final widths = {
        for (final l in ['أ', 'ب', 'ج', 'د'])
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.text(l),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .width
              .round(),
      };
      expect(widths, hasLength(1));
    });
  });

  group('AppTextField', () {
    Border ringOf(WidgetTester tester) =>
        (tester
                        .widget<AnimatedContainer>(
                          find.byKey(AppTextField.frameKey),
                        )
                        .decoration!
                    as BoxDecoration)
                .border!
            as Border;

    testWidgets('idle: a 2 pt ground.lip ring; focused: primary', (
      tester,
    ) async {
      await pumpDesignComponent(
        tester,
        SizedBox(
          width: 253,
          child: AppTextField(
            controller: TextEditingController(text: 'حمادة'),
            semanticLabel: 'اسمك',
          ),
        ),
      );
      expect(ringOf(tester).top.color, ColorTokens.groundLip);
      expect(ringOf(tester).top.width, 2);
      expect(tester.getSize(find.byType(AppTextField)).height, 52);
      await tester.tap(find.byType(AppTextField));
      await tester.pumpAndSettle();
      expect(ringOf(tester).top.color, ColorTokens.primary);
    });
  });
}
