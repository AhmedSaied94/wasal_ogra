import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../../../helpers/design_component.dart';
import '../../../helpers/trip.dart';

// The lip press every control shares (contracts/components.md "Rules").

const _key = Key('face');

Widget _pressable({
  VoidCallback? onTap,
  bool enabled = true,
  double? pressedOpacity,
  bool lip = true,
  Size size = const Size(120, 50),
}) => Pressable(
  onTap: onTap ?? () {},
  enabled: enabled,
  lip: lip ? LipTokens.primary : null,
  borderRadius: BorderRadius.circular(RadiusTokens.l),
  pressedOpacity: pressedOpacity,
  semanticLabel: 'go',
  child: SizedBox.fromSize(
    key: _key,
    size: size,
    child: const ColoredBox(color: ColorTokens.primary),
  ),
);

/// The press offset applied to the face: 0 when nothing moves it.
double _offset(WidgetTester tester) {
  final transforms = find.ancestor(
    of: find.byKey(_key),
    matching: find.byType(Transform),
  );
  if (transforms.evaluate().isEmpty) return 0;
  return tester
      .widget<Transform>(transforms.first)
      .transform
      .getTranslation()
      .y;
}

/// The lip under the face, or null without one.
BoxShadow? _lip(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.ancestor(of: find.byKey(_key), matching: find.byType(DecoratedBox)),
  );
  for (final box in boxes) {
    final shadows = (box.decoration as BoxDecoration).boxShadow;
    if (shadows != null && shadows.isNotEmpty) return shadows.single;
  }
  return null;
}

void main() {
  testWidgets('at rest: the full lip and no offset', (tester) async {
    await pumpDesignComponent(tester, _pressable());
    expect(_offset(tester), 0);
    expect(_lip(tester)!.offset, const Offset(0, LipTokens.primaryDepth));
    expect(_lip(tester)!.blurRadius, 0);
    expect(_lip(tester)!.color, LipTokens.primary.color);
  });

  testWidgets('mid-press: half the lip down, the lip shrinks; release '
      'returns', (tester) async {
    var taps = 0;
    await pumpDesignComponent(tester, _pressable(onTap: () => taps++));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_key)),
    );
    await tester.pump();
    await tester.pump(MotionTokens.press ~/ 2);
    final offset = _offset(tester);
    expect(offset, greaterThan(0));
    expect(offset, lessThan(LipTokens.primaryDepth));
    expect(
      _lip(tester)!.offset.dy,
      closeTo(LipTokens.primaryDepth - offset, 0.001),
    );
    await tester.pump(MotionTokens.press);
    expect(_offset(tester), LipTokens.primaryDepth);
    expect(_lip(tester)?.offset.dy ?? 0, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(_offset(tester), 0);
    expect(_lip(tester)!.offset, const Offset(0, LipTokens.primaryDepth));
  });

  testWidgets('each press ticks the haptic once', (tester) async {
    final haptics = FakeHaptics();
    await pumpDesignComponent(tester, _pressable(), haptics: haptics);
    await tester.tap(find.byKey(_key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_key));
    await tester.pumpAndSettle();
    expect(haptics.felt, ['selection', 'selection']);
  });

  testWidgets('with vibration off a press is silent', (tester) async {
    final haptics = FakeHaptics();
    await pumpDesignComponent(
      tester,
      _pressable(),
      haptics: haptics,
      vibration: false,
    );
    await tester.tap(find.byKey(_key));
    await tester.pumpAndSettle();
    expect(haptics.felt, isEmpty);
  });

  testWidgets('disabled: 45% opacity, no lip, no press, no tap', (
    tester,
  ) async {
    var taps = 0;
    final haptics = FakeHaptics();
    final semantics = tester.ensureSemantics();
    await pumpDesignComponent(
      tester,
      _pressable(onTap: () => taps++, enabled: false),
      haptics: haptics,
    );
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.byKey(_key), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0.45);
    expect(_lip(tester), isNull);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_key)),
    );
    await tester.pump(MotionTokens.press);
    expect(_offset(tester), 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(haptics.felt, isEmpty);
    final node = tester.getSemantics(find.byType(Pressable));
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('a 20×20 face still has a 44×44 hit area', (tester) async {
    var taps = 0;
    await pumpDesignComponent(
      tester,
      _pressable(onTap: () => taps++, size: const Size(20, 20)),
    );
    final hit = tester.getSize(find.byType(Pressable));
    expect(hit.width, greaterThanOrEqualTo(44));
    expect(hit.height, greaterThanOrEqualTo(44));
    // A tap 20 pt beside the face still lands.
    await tester.tapAt(
      tester.getCenter(find.byKey(_key)) + const Offset(20, 0),
    );
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('its semantics: a button with the label, tappable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpDesignComponent(tester, _pressable());
    final node = tester.getSemantics(find.byType(Pressable));
    expect(node.label, 'go');
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('tertiary: pressed means 70% opacity, no offset', (tester) async {
    await pumpDesignComponent(
      tester,
      _pressable(pressedOpacity: 0.7, lip: false),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_key)),
    );
    await tester.pump();
    await tester.pump(MotionTokens.press * 2);
    expect(_offset(tester), 0);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.byKey(_key), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, closeTo(0.7, 0.001));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion still presses', (tester) async {
    await pumpDesignComponent(tester, _pressable(), reducedMotion: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_key)),
    );
    await tester.pump();
    await tester.pump(MotionTokens.press * 2);
    expect(_offset(tester), LipTokens.primaryDepth);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
