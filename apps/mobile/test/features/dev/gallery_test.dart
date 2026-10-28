import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/dev/gallery/components_page.dart';
import 'package:wassal/features/dev/gallery/gallery_entry.dart';
import 'package:wassal/features/dev/gallery/gallery_screen.dart';
import 'package:wassal/features/dev/gallery/tokens_page.dart';

import '../../helpers/home.dart';
import '../../helpers/pump_app.dart';

// The design gallery of internal builds (specs/008.5-m21-design-refresh,
// research R4, contracts/components.md "The gallery").

/// The components of contracts/components.md "The set", from its first
/// table (`lib/core/theme/components/`).
Set<String> _contractComponents() {
  final contract = File(
    '../../specs/008.5-m21-design-refresh/contracts/components.md',
  ).readAsLinesSync();
  final start = contract.indexWhere((l) => l.startsWith('## The set'));
  final end = contract.indexWhere((l) => l.startsWith('`lib/features/'), start);
  final names = <String>{};
  for (final line in contract.sublist(start, end)) {
    final cells = line.split('|');
    if (cells.length < 4) continue;
    for (final m in RegExp('`([A-Z][A-Za-z]+)`').allMatches(cells[2])) {
      names.add(m.group(1)!);
    }
  }
  return names;
}

/// The shared components later features add, which 008.5's contract
/// doesn't list: M08's passenger face (specs/013-m08-home-result T011).
const _laterComponents = {'PassengerAvatar'};

/// Opens the gallery from Home on [flavor]. It animates without end (the
/// loader, the coach hand), so frames are pumped, never settled.
Future<void> _openGallery(WidgetTester tester) async {
  await pumpWassalApp(tester, initialLocation: '/home');
  await openDebugSheet(tester);
  final entry = find.byType(GalleryEntry);
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final flavor in [Flavor.dev, Flavor.staging]) {
    testWidgets('on ${flavor.name}, Home has a gallery button', (tester) async {
      await pumpWassalApp(tester, flavor: flavor, initialLocation: '/home');
      // In the testers' sheet since M08.
      await openDebugSheet(tester);
      expect(find.byType(GalleryEntry), findsOne);
    });
  }

  testWidgets('the button opens GalleryScreen, and back closes it', (
    tester,
  ) async {
    await _openGallery(tester);
    expect(find.byType(GalleryScreen), findsOne);
    expect(currentLocation(tester), '/home', reason: 'no route of its own');
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GalleryScreen), findsNothing);
  });

  testWidgets('a section per component of contracts/components.md', (
    tester,
  ) async {
    final contract = _contractComponents();
    expect(contract, hasLength(greaterThan(25)));
    final expected = {...contract, ..._laterComponents};
    expect(gallerySections.map((s) => s.name).toSet(), expected);
    await _openGallery(tester);
    for (final name in expected) {
      expect(
        find.byKey(GallerySection.keyOf(name), skipOffstage: false),
        findsOne,
        reason: name,
      );
    }
  });

  testWidgets('the tokens page names every colour swatch', (tester) async {
    await _openGallery(tester);
    await tester.tap(find.text('Tokens'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    for (final name in ColorTokens.named.keys) {
      expect(
        find.descendant(
          of: find.byKey(TokensPage.swatchKey(name), skipOffstage: false),
          matching: find.text(name, skipOffstage: false),
          skipOffstage: false,
        ),
        findsOne,
        reason: name,
      );
    }
  });

  testWidgets('the digit switch changes the numbers shown', (tester) async {
    await _openGallery(tester);
    expect(find.textContaining('١٬٢٤٠', skipOffstage: false), findsWidgets);
    expect(find.textContaining('1,240', skipOffstage: false), findsNothing);
    await tester.tap(find.text('Western'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('1,240', skipOffstage: false), findsWidgets);
    expect(find.textContaining('١٬٢٤٠', skipOffstage: false), findsNothing);
  });

  group('prod', () {
    testWidgets('has no gallery button', (tester) async {
      await pumpWassalApp(
        tester,
        flavor: Flavor.prod,
        initialLocation: '/home',
      );
      expect(find.byType(GalleryEntry), findsNothing);
    });

    testWidgets('no route leads to the gallery', (tester) async {
      final container = await pumpWassalApp(tester, flavor: Flavor.prod);
      for (final d in destinations) {
        expect(d.name.toLowerCase(), isNot(contains('gallery')));
        expect(d.path?.toLowerCase() ?? '', isNot(contains('gallery')));
      }
      final router = container.read(routerProvider);
      router.go('/gallery');
      await tester.pumpAndSettle();
      expect(find.byType(GalleryScreen), findsNothing);
    });
  });
}
