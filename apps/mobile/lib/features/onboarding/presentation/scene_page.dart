import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/domain/first_session.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';

/// A scene the app plays by itself (specs/012-m07-onboarding/contracts/
/// scenes.md "Routes"), and what its end writes. The opening
/// (`/onboarding/intro`) writes step 1 when it opens and its done time when
/// it ends, then goes to the Name card (with [then], the playtest card's,
/// passed on). An after-trip scene
/// (`/onboarding/scene/:sceneId`) is marked seen, waits for the ask after
/// it, and goes to [then] when that is a trip or Home.
class ScenePage extends ConsumerStatefulWidget {
  /// The pack's opening scene, then the Name card.
  const ScenePage.opening({this.then, super.key}) : sceneId = null;

  /// The pack's scene [sceneId], then [then].
  const ScenePage({required String this.sceneId, this.then, super.key});

  /// The scene [sceneId] of the pack; null for the opening.
  final String? sceneId;

  /// Where an after-trip scene goes next, as the link gave it; where the
  /// Name card goes after the opening.
  final String? then;

  /// Where the opening goes next.
  static const afterOpening = '/onboarding/name';

  @override
  ConsumerState<ScenePage> createState() => _ScenePageState();
}

class _ScenePageState extends ConsumerState<ScenePage> {
  bool _leaving = false;

  /// Raised when the end's writes fail: the scene plays again, and its end
  /// writes again.
  int _attempt = 0;

  FirstSessionFlagsNotifier get _flags =>
      ref.read(firstSessionFlagsProvider.notifier);

  @override
  void initState() {
    super.initState();
    if (widget.sceneId == null) unawaited(_flags.reachStep(openingStep));
  }

  /// The scene's end; [played] is false for a scene the pack lacks.
  Future<void> _finished({bool played = true}) async {
    if (_leaving) return;
    _leaving = true;
    final String next;
    final bool written;
    if (widget.sceneId case final sceneId?) {
      final service = ref.read(firstSessionServiceProvider);
      written = await _written(() async {
        await service.sceneSeen(sceneId);
        await service.afterScene();
      });
      next = safeThen(widget.then);
    } else {
      written = await _written(_flags.markOpeningDone);
      next = switch (widget.then) {
        final then? => Uri(
          path: ScenePage.afterOpening,
          queryParameters: {'then': then},
        ).toString(),
        null => ScenePage.afterOpening,
      };
    }
    if (!mounted) return;
    if (!written && played) {
      // Leaving would bring the scene straight back, on this same page.
      setState(() {
        _leaving = false;
        _attempt++;
      });
      return;
    }
    context.go(next);
  }

  /// Runs [write]; false, with the failure reported, when it throws.
  static Future<bool> _written(Future<void> Function() write) async {
    try {
      await write();
      return true;
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'onboarding',
        ),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(contentSourceProvider);
    final id = widget.sceneId ?? ref.watch(tutorialPlanProvider).openingScene;
    final scene = id == null ? null : sceneOf(content, id);
    if (id == null || scene == null) {
      // The router sends a pack without its opening on. A due scene the
      // active pack lacks is passed as seen, so it never comes back.
      if (widget.sceneId != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_finished(played: false)),
        );
      }
      return const ColoredBox(color: ColorTokens.dashboardBg);
    }
    return ScenePlayer(
      key: ValueKey(_attempt),
      title: chapterOfScene(content, id)?.title.arEg ?? '',
      scene: scene,
      driverName: ref.watch(driverNameProvider),
      onFinished: () => unawaited(_finished()),
    );
  }
}
