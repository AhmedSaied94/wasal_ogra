// Sharing a panel (specs/015-m10-apartment-story, contracts/scene-viewer.md
// "Share", T080): the fake gateway gets a 358×540 picture at ×3 with the
// still drawing, offline; a failure shows M08's share error.
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/bootstrap/app.dart' show appLocale;
import 'package:wassal/core/platform/share_gateway.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';
import 'package:wassal/features/story/presentation/scene_panel_share.dart';
import 'package:wassal/features/story/presentation/scene_viewer_page.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

import '../../helpers/fake_share_gateway.dart';
import '../../helpers/lines.dart';
import '../../helpers/server_status.dart';

/// 358 × 3 and 540 × 3.
const _width = 1074;
const _height = 1620;

(int, int) _sizeOf(Uint8List png) {
  final header = ByteData.sublistView(png);
  return (header.getUint32(16), header.getUint32(20));
}

Future<Color> _colorAt(WidgetTester tester, Uint8List png, int x, int y) async {
  final pixels = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  final rgba = pixels!.getUint32((y * _width + x) * 4);
  return Color(((rgba & 0xFF) << 24) | (rgba >> 8));
}

/// Lets the share run: the frames, then the capture and the encoding, which
/// take real time.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the share never finished');
}

/// The viewer on the last panel of `opening`, the share offered.
Future<(ProviderContainer, FakeShareGateway)> _lastPanel(
  WidgetTester tester,
) async {
  final gateway = FakeShareGateway();
  final (container, _) = await pumpLinesApp(
    tester,
    pack: samplePackJsonForLines(),
    location: '/story/scene/opening',
    state: playerState(),
    overrides: [shareGatewayProvider.overrideWithValue(gateway)],
  );
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.byKey(SceneViewerPage.panelKey));
    await tester.pumpAndSettle();
  }
  expect(find.byKey(SceneViewerPage.shareKey), findsOneWidget);
  return (container, gateway);
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(appLocale);
  });

  testWidgets('a 358×540 picture at ×3, with its caption, named after the '
      'scene and panel', (tester) async {
    final (_, gateway) = await _lastPanel(tester);
    await tester.tap(find.byKey(SceneViewerPage.shareKey));
    await tester.pump();
    await _until(tester, () => gateway.shared.isNotEmpty);
    final shared = gateway.shared.single;
    expect(_sizeOf(shared.png), (_width, _height));
    expect(shared.fileName, 'wassal_scene_opening_3.png');
    expect(shared.text, l10n.shareSceneText);
    // Where an iPad anchors the sheet: the button.
    expect(shared.origin, tester.getRect(find.byKey(SceneViewerPage.shareKey)));
    // The wordmark strip along the foot is `sun`; the sky at the top is the
    // panel's own, not the viewer's dark ground.
    expect(
      await _colorAt(tester, shared.png, _width ~/ 2, _height - 4),
      ColorTokens.sun,
    );
    expect(
      await _colorAt(tester, shared.png, _width ~/ 2, 4),
      isNot(ColorTokens.dashboardBg),
    );
    // The viewer is where it was.
    expect(find.byKey(SceneViewerPage.shareKey), findsOneWidget);
    expect(find.byKey(ScenePanelShare.stripKey), findsNothing);
  });

  test('the picture names the driver «الأسطى», never the player', () {
    // The share path never receives the typed name, so a picture can't carry
    // it (T145); the viewer is the only place that shows it.
    expect(shareSpeakerName(l10n, ScenePlayer.driver), l10n.driverNameDefault);
    expect(shareSpeakerName(l10n, 'salma'), l10n.sceneSpeaker('salma'));
  });

  testWidgets('offline: nothing is fetched', (tester) async {
    final (container, gateway) = await _lastPanel(tester);
    (container.read(serverStatusProvider.notifier) as PinnedServerStatus).pin(
      const ServerStatusState(reach: Reach.offline),
    );
    await tester.pump();
    await tester.tap(find.byKey(SceneViewerPage.shareKey));
    await tester.pump();
    await _until(tester, () => gateway.shared.isNotEmpty);
    expect(_sizeOf(gateway.shared.single.png), (_width, _height));
  });

  testWidgets('a failure: the share error, and nothing else', (tester) async {
    final (_, gateway) = await _lastPanel(tester);
    gateway.failWith = PlatformException(code: 'share');
    await tester.tap(find.byKey(SceneViewerPage.shareKey));
    await tester.pump();
    await _until(tester, () => gateway.calls == 1);
    await tester.pump();
    expect(find.text(l10n.shareFailed), findsOneWidget);
    expect(find.byType(AppToast), findsOneWidget);
    expect(tester.takeException(), isA<PlatformException>());
    expect(gateway.shared, isEmpty);
    expect(find.byKey(SceneViewerPage.continueKey), findsOneWidget);
  });

  testWidgets('a second tap while sharing does nothing', (tester) async {
    final (_, gateway) = await _lastPanel(tester);
    gateway.hold();
    await tester.tap(find.byKey(SceneViewerPage.shareKey));
    await tester.pump();
    await _until(tester, () => gateway.calls == 1);
    await tester.tap(find.byKey(SceneViewerPage.shareKey));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(gateway.calls, 1);
    gateway.release();
    await tester.pump();
  });
}
