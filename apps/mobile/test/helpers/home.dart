// Home in tests (specs/013-m08-home-result).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/features/home/presentation/debug_sheet.dart';

/// Opens the testers' sheet from Home's debug button (internal builds), and
/// lets it slide in. Its tools never settle (the loader and the coach
/// hand loop), so frames are pumped.
Future<void> openDebugSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(HomeDebugButton.buttonKey));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// A Text showing [text], without the bidi isolates numbers carry.
Finder shows(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(RegExp('[\u2066-\u2069]'), '') == text,
);

/// A semantics node labelled [text], with or without the bidi isolates
/// numbers carry.
Finder labelled(String text) => find.bySemanticsLabel(
  RegExp(
    '^[\u2066-\u2069]*'
    '${text.split('').map(RegExp.escape).join('[\u2066-\u2069]*')}'
    '[\u2066-\u2069]*\$',
  ),
);
