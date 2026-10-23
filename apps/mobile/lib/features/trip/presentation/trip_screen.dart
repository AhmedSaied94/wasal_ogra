// The trip screen (specs/008.5-m21-design-refresh, contracts/trip-layout.md):
// the HUD under the top inset, the scene with its overlays, and the
// dashboard over the scene's last 16 pt, with the cards over them by phase.
// It hides the system bars, clamps text scale to 1.3, plays the cues the
// player has switched on, pauses when the app leaves the foreground, and
// leaves when the trip ends.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/audio_haptics/audio_haptics_providers.dart';
import 'package:wassal/core/audio_haptics/sfx.dart';
import 'package:wassal/core/routing/trip_pause_overlay.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/application/trip_controller.dart';
import 'package:wassal/features/trip/application/trip_phase.dart';
import 'package:wassal/features/trip/domain/cues.dart';
import 'package:wassal/features/trip/domain/scene_layout.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/features/trip/presentation/cards/booster_card.dart';
import 'package:wassal/features/trip/presentation/cards/dispute_card.dart';
import 'package:wassal/features/trip/presentation/cards/failure_card.dart';
import 'package:wassal/features/trip/presentation/cards/no_fuel_card.dart';
import 'package:wassal/features/trip/presentation/cards/pause_card.dart';
import 'package:wassal/features/trip/presentation/cards/retry_card.dart';
import 'package:wassal/features/trip/presentation/dashboard/dashboard.dart';
import 'package:wassal/features/trip/presentation/overlays/banner.dart';
import 'package:wassal/features/trip/presentation/overlays/bubbles_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/choices_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/hint_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/hit_areas.dart';
import 'package:wassal/features/trip/presentation/overlays/patches_layer.dart';
import 'package:wassal/features/trip/presentation/overlays/station_sign_name.dart';
import 'package:wassal/features/trip/presentation/overlays/story_strip.dart';
import 'package:wassal/features/trip/presentation/playtest/debug_panel.dart';
import 'package:wassal/features/trip/presentation/overlays/token_layer.dart';
import 'package:wassal/features/trip/presentation/scene/trip_game.dart';
import 'package:wassal/features/trip/presentation/top_bar/top_bar.dart';
import 'package:wassal/features/trip/presentation/trip_scope.dart';
import 'package:wassal/features/trip/trip_providers.dart';

class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  late final ProviderSubscription<TripController> _subscription;
  late final TripController _controller;
  late final ValueNotifier<TripModel> _model;
  late final TripControls _controls;
  late final StreamSubscription<TripModel> _models;
  late final StreamSubscription<TripCue> _cues;
  late final AppLifecycleListener _lifecycle;
  late final bool _drivesClock;
  TripGame? _game;
  bool _left = false;

  /// Trip screens mounted: during a replacement by another trip, the old
  /// one is disposed after the new one set the bars.
  static int _mounted = 0;

  @override
  void initState() {
    super.initState();
    _mounted++;
    _subscription = ref.listenManual(
      tripControllerProvider(widget.tripId),
      (_, _) {},
    );
    _controller = _subscription.read();
    _drivesClock = ref.read(tripFrameDrivenProvider);
    _model = ValueNotifier(_controller.model);
    _controls = TripControls(_controller);
    _models = _controller.models.listen(_onModel);
    _cues = _controller.cues.listen(_onCue);
    _lifecycle = AppLifecycleListener(
      onInactive: _pauseForLifecycle,
      onHide: _pauseForLifecycle,
      onPause: _pauseForLifecycle,
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(ref.read(sfxPlayerProvider).load());
    _onModel(_controller.model);
  }

  @override
  void dispose() {
    if (--_mounted == 0) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _lifecycle.dispose();
    unawaited(_models.cancel());
    unawaited(_cues.cancel());
    _controls.dispose();
    _model.dispose();
    _subscription.close();
    super.dispose();
  }

  void _pauseForLifecycle() => _controller.pause(PauseReason.lifecycle);

  void _onModel(TripModel model) {
    final old = _model.value;
    // What the bands and cards are built from, besides the view.
    final reshaped =
        model.phase != old.phase ||
        model.retry != old.retry ||
        model.restartEnabled != old.restartEnabled ||
        model.nextLiterAtMs != old.nextLiterAtMs ||
        model.boosterCard != old.boosterCard;
    _model.value = model;
    if (reshaped && mounted) setState(() {});
    _syncGame(model);
    if (model.exit case final exit?) _leave(exit);
  }

  /// Keeps the scene's frames in step with the phase.
  void _syncGame(TripModel model) {
    final game = _game;
    if (game == null) return;
    if (!_drivesClock) {
      game.stepEngine(stepTime: 0);
      return;
    }
    if (model.phase == TripPhase.running) {
      if (game.paused) game.resumeEngine();
    } else if (game.paused) {
      // Stopped: draw the change once.
      game.stepEngine(stepTime: 0);
    }
  }

  void _onCue(TripCue cue) {
    _controls.onCue(cue);
    final settings = ref.read(tripSettingsProvider);
    switch (cue) {
      case SoundCue(:final sound) when settings.soundOn:
        ref.read(sfxPlayerProvider).play(sfxOf(sound));
      case HapticCue(:final kind) when settings.hapticsOn:
        final haptics = ref.read(hapticsProvider);
        switch (kind) {
          case HapticKind.light:
            haptics.light();
          case HapticKind.heavy:
            haptics.heavy();
        }
      default:
    }
  }

  void _leave(TripExit exit) {
    if (_left) return;
    _left = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.of(context);
      switch (exit) {
        case ExitToResult(:final tripId, :final result):
          unawaited(
            router.pushReplacement('/trip/$tripId/result', extra: result),
          );
        case ExitToHome():
          router.go('/home');
        case ExitToTrip(:final tripId):
          unawaited(router.pushReplacement('/trip/$tripId'));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onBack() {
    switch (_controller.phase) {
      case TripPhase.running:
        _controller.pause(PauseReason.back);
      case TripPhase.paused:
        _controller.resume();
      case TripPhase.noFuel:
        context.go('/home');
      case TripPhase.boosterCard:
        _controller.closeBoosterCard();
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    // The debug panel's tier switch redraws the seats in this trip.
    ref.listen(passengerArtProvider, (_, art) => _game?.art = art);
    return TripBackGuard(
      onBack: _onBack,
      child: TripScope(
        controller: _controller,
        model: _model,
        controls: _controls,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: tripMaxTextScale,
          // The bars are hidden; swiped in, they sit on the HUD and the
          // dashboard.
          child: SystemBars(
            bottom: ColorTokens.dashboardBg,
            child: Material(
              color: ColorTokens.ground,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bottom = MediaQuery.paddingOf(context).bottom;
                  final zones = TripZones(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight - bottom,
                    viewPaddingTop: MediaQuery.viewPaddingOf(context).top,
                  );
                  return Stack(
                    children: [
                      // Over 430 wide the zones keep 390, centred, and the
                      // cabin's wall reaches the screen's edges behind them.
                      if (zones.left > 0)
                        Positioned(
                          top: zones.sceneTop,
                          left: 0,
                          right: 0,
                          height: zones.scene,
                          child: const ColoredBox(color: ColorTokens.sceneWall),
                        ),
                      Positioned(
                        top: zones.sceneTop,
                        left: zones.left,
                        width: zones.width,
                        height: zones.scene,
                        child: _scene(),
                      ),
                      Positioned(
                        top: zones.inset,
                        left: zones.left,
                        width: zones.width,
                        height: zones.hud,
                        child: TripHud(
                          onPause: () => _controller.pause(PauseReason.button),
                          onDebug: ref.read(flavorProvider) == Flavor.prod
                              ? null
                              : () => _controller.pause(PauseReason.debugPanel),
                        ),
                      ),
                      Positioned(
                        top: zones.dashboardTop,
                        left: zones.left,
                        width: zones.width,
                        height: zones.dashboard + bottom,
                        child: const TripDashboard(),
                      ),
                      Positioned.fill(child: _card()),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scene() {
    final definition = _controller.session?.facts.definition;
    if (definition == null) return const SizedBox.expand();
    final seats = definition.seats;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = SceneLayout(
          seats,
          vehicle: definition.vehicleId,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );
        final game = _gameFor(definition, context);
        return Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(child: GameWidget(game: game)),
            ),
            // On the window's sign, under everything else.
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(child: StationSignName(layout: layout)),
              ),
            ),
            Positioned.fill(child: PatchesLayer(layout: layout)),
            Positioned.fill(child: TokenLayer(layout: layout)),
            Positioned.fill(child: HitAreas(layout: layout)),
            // Over the hit areas, so a note on the floor takes its tap.
            Positioned.fill(child: DroppedLayer(layout: layout)),
            Positioned.fill(child: ChoicesLayer(layout: layout)),
            Positioned.fill(
              child: IgnorePointer(child: BubblesLayer(layout: layout)),
            ),
            Positioned.fill(
              child: IgnorePointer(child: HintLayer(layout: layout)),
            ),
            const Positioned.fill(child: IgnorePointer(child: FareBanner())),
            // At the scene's top, over the back window.
            const Positioned(
              top: SpaceTokens.s8,
              left: SpaceTokens.s10,
              right: SpaceTokens.s10,
              child: IgnorePointer(child: StoryStrip()),
            ),
          ],
        );
      },
    );
  }

  TripGame _gameFor(TripDefinition definition, BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final game = _game ??= _newGame(definition, reduced);
    game.reduceMotion = reduced;
    return game;
  }

  TripGame _newGame(TripDefinition definition, bool reduced) {
    final game = TripGame(
      controller: _controller,
      seats: definition.seats,
      vehicle: definition.vehicleId,
      art: ref.read(passengerArtProvider),
      reduceMotion: reduced,
      drivesClock: _drivesClock,
    );
    // The first frames mount the scene's parts, also when nothing ticks: a
    // step a frame, since each mounts one level (the stage, then its parts)
    // and a step only arms the next tick.
    unawaited(
      game.mounted.then((_) async {
        for (var i = 0; i < 3; i++) {
          if (_drivesClock || !mounted) return;
          game.stepEngine(stepTime: 0);
          await SchedulerBinding.instance.endOfFrame;
        }
      }),
    );
    return game;
  }

  Widget _card() {
    final model = _model.value;
    final retry = model.retry;
    // A purchase's or a revive's retry is said on its card.
    if (retry != null &&
        retry != TripRetry.purchase &&
        retry != TripRetry.revive) {
      return RetryCard(
        retry: retry,
        onRetry: () => unawaited(_controller.retry()),
        onHome: retry == TripRetry.start ? () => context.go('/home') : null,
      );
    }
    return switch (model.phase) {
      TripPhase.noFuel => NoFuelCard(
        nextLiterAtMs: model.nextLiterAtMs,
        onFuel: () => context.go('/shop/fuel'),
        onHome: () => context.go('/home'),
      ),
      TripPhase.disputeOpen => const DisputeCard(),
      TripPhase.boosterCard => switch (model.boosterCard) {
        final card? => BoosterCard(
          card: card,
          retry: retry,
          onBuy: () => unawaited(_controller.buyBooster()),
          onClose: _controller.closeBoosterCard,
        ),
        null => const SizedBox.shrink(),
      },
      TripPhase.failed => switch (model.view?.failSummary) {
        final summary? => FailureCard(
          summary: summary,
          retry: retry,
          restartEnabled: model.restartEnabled,
          onRevive: () => unawaited(_controller.revive()),
          onRestart: () => unawaited(_controller.restart()),
          onHome: () => unawaited(_controller.leave()),
        ),
        null => const SizedBox.shrink(),
      },
      TripPhase.paused when model.pauseReason == PauseReason.debugPanel =>
        switch (_controller.debugSnapshot) {
          (:final state, :final record)? => DebugPanel(
            state: state,
            record: record,
            onClose: _controller.resume,
          ),
          null => const SizedBox.shrink(),
        },
      TripPhase.paused => PauseCard(
        restartEnabled: model.restartEnabled,
        onResume: _controller.resume,
        onRestart: () => unawaited(_controller.restart()),
        onHome: () => unawaited(_controller.leave()),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The stand-in file of each cue's sound.
Sfx sfxOf(CueSound sound) => switch (sound) {
  CueSound.coin => Sfx.coin,
  CueSound.notePass => Sfx.notePass,
  CueSound.call => Sfx.call,
  CueSound.horn => Sfx.horn,
  CueSound.fight => Sfx.fight,
  CueSound.thanks => Sfx.thanks,
  CueSound.wrong => Sfx.wrong,
  CueSound.bump => Sfx.bump,
  CueSound.alert => Sfx.alert,
};
