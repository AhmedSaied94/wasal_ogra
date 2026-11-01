// The story's viewer (specs/015-m10-apartment-story, contracts/
// scene-viewer.md "The viewer", research R12), built to the `SceneViewer`
// artboard: one scene, or a chapter's unlocked ones in story order, each
// recorded as seen when it ends, is skipped or is left.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey, SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/content_source.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/platform/offscreen_render.dart';
import 'package:wassal/core/platform/share_gateway.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/core/theme/tokens/scene_turn_tokens.dart';
import 'package:wassal/features/onboarding/domain/panel_turns.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';
import 'package:wassal/features/story/application/story_service.dart';
import 'package:wassal/features/story/domain/scene_sequence.dart';
import 'package:wassal/features/story/presentation/scene_panel_share.dart';
import 'package:wassal/features/story/presentation/scene_panel_view.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// How long the animated panels' turns last (specs/012.5-m22-animated-scenes,
/// research R5), as M07's player counts them.
final _turnTimings = TurnTimings(
  leadIn: SceneTurnTokens.leadIn,
  perLetter: SceneTurnTokens.perLetter,
  min: SceneTurnTokens.min,
  max: SceneTurnTokens.max,
  pause: SceneTurnTokens.pause,
);

class SceneViewerPage extends ConsumerStatefulWidget {
  /// `/story/scene/:sceneId?then=…`: that scene.
  const SceneViewerPage.scene({
    required String this.sceneId,
    this.then,
    super.key,
  }) : chapterId = null;

  /// `/story/:chapterId?then=…`: the chapter's unlocked scenes.
  const SceneViewerPage.chapter({
    required ChapterId this.chapterId,
    this.then,
    super.key,
  }) : sceneId = null;

  final String? sceneId;
  final ChapterId? chapterId;
  final String? then;

  static const skipKey = Key('SceneViewer.skip');
  static const panelKey = Key('SceneViewer.panel');
  static const shareKey = Key('SceneViewer.share');
  static const continueKey = Key('SceneViewer.continue');
  static const titleKey = Key('SceneViewer.title');

  /// `SceneViewer` box 4: the panel's height on the reference frame. A
  /// shorter screen gives it less.
  static const double panelHeight = ScenePanelView.frameHeight;

  /// Boxes 19 and 21: the last panel's buttons are 64 high, «شارك» 1 part and
  /// «كمّل» 2, 10 apart.
  static const double actionsHeight = 64;
  static const double _actionsGap = 10;

  /// Box 19 is 124 wide: its icon sits 22.7 in from the edge.
  static const double _shareSidePadding = 22.7;
  static const double _shareRadius = 22;
  static const double _shareIcon = 22;

  @override
  ConsumerState<SceneViewerPage> createState() => _SceneViewerPageState();
}

class _SceneViewerPageState extends ConsumerState<SceneViewerPage>
    with TickerProviderStateMixin {
  List<(Chapter, Scene)>? _sequence;
  int _scene = 0;
  int _panel = 0;

  /// Counts every panel shown, across scenes, so the switcher slides on a
  /// scene change as on a panel change.
  int _step = 0;

  bool _leaving = false;

  /// A record is on its way for «كمّل», «تخطّى» or back.
  bool _advancing = false;
  bool _sharing = false;

  /// The scenes whose last panel was reached, already recorded.
  final _recorded = <String>{};

  /// The panel [_clock] belongs to, as `(step)`.
  int? _revealOf;

  /// The turns of an animated panel; null for a still one (the stagger).
  PanelTurns? _turns;

  /// The bubbles' clock, while they appear; one per panel.
  AnimationController? _clock;
  TurnsAt? _at;

  /// All of the panel's bubbles show and nobody talks.
  bool _revealed = true;

  /// The spoken lines of the panel on screen.
  int _spokenCount = 0;

  /// Before the first bubble, the panel slides in; then one every 150 ms.
  static const _stagger = Duration(milliseconds: 150);
  static const _lead = MotionTokens.sheetIn;

  /// `SceneViewer` box 4's gaps: the header, the panel, the dots.
  static const double _gap = 16;
  static const double _bottom = 28;
  static const double _dots = 10;
  static const double _belowPanel = _gap + _dots;

  final _shareButton = GlobalKey();

  Scene get _currentScene => _sequence![_scene].$2;
  Chapter get _currentChapter => _sequence![_scene].$1;
  Panel get _currentPanel => _currentScene.panels[_panel];
  bool get _lastPanel => _panel + 1 >= _currentScene.panels.length;
  bool get _lastScene => _scene + 1 >= _sequence!.length;

  // ---- leaving and recording ----

  /// Where the viewer goes: `then` when it gave a place, else back, else the
  /// apartment (contracts/scene-viewer.md "Routes").
  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    final then = storyThen(widget.then);
    if (then != null) {
      context.go(then);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/apartment');
    }
  }

  /// Records [scene] once per visit; the economy refuses a replay without
  /// storing it, and the service keeps a failed write's id for the next call.
  /// A failed write is reported, never thrown: the player still moves on, and
  /// the scene comes back as waiting (M07's `ScenePage._written` does the same).
  Future<void> _record(Scene scene) async {
    try {
      await ref.read(storyServiceProvider).recordSeen(scene.sceneId);
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'story'),
      );
    }
  }

  /// «تخطّى» and back: every scene reached so far, then out.
  Future<void> _exit() async {
    if (_leaving || _advancing) return;
    _advancing = true;
    try {
      final reached = _sequence == null
          ? const <Scene>[]
          : [for (var i = 0; i <= _scene; i++) _sequence![i].$2];
      for (final scene in reached) {
        await _record(scene);
      }
    } finally {
      _advancing = false;
    }
    _leave();
  }

  /// «كمّل»: record the scene, then the next one's first panel, or out. A
  /// second tap while the record is on its way does nothing, or it would step
  /// past the sequence's end.
  Future<void> _continue() async {
    if (_leaving || _advancing) return;
    _advancing = true;
    try {
      final scene = _currentScene;
      final last = _lastScene;
      await _record(scene);
      if (!mounted) return;
      if (last) {
        _leave();
        return;
      }
      setState(() {
        _scene++;
        _panel = 0;
        _step++;
      });
      _announce();
    } finally {
      _advancing = false;
    }
  }

  // ---- panels ----

  /// A tap on the panel: show the bubbles at once while they are still
  /// appearing, else the next panel; nothing on the last.
  void _tapPanel() {
    if (_leaving || _sequence == null) return;
    if (_appearing) {
      setState(_endReveal);
      return;
    }
    if (_lastPanel) return;
    setState(() {
      _panel++;
      _step++;
    });
    _announce();
  }

  /// A panel was shown by a tap: say which.
  void _announce() {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.read(numberFormatterProvider);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        l10n.introPageOf(
          numbers.integer(_panel + 1),
          numbers.integer(_currentScene.panels.length),
        ),
        Directionality.of(context),
      ),
    );
  }

  /// Reaching a scene's last panel records the scene, so a crash after it
  /// loses nothing. Once per scene, after the frame that shows it.
  void _recordLastPanel(int step) {
    if (!mounted || step != _step || !_lastPanel) return;
    if (_recorded.add(_currentScene.sceneId)) {
      unawaited(_record(_currentScene));
    }
  }

  // ---- the bubbles' reveal ----

  /// The bubbles are still on their way: the clock runs and the last has not
  /// started.
  bool get _appearing => _clock != null && !(_at?.lastStarted ?? true);

  /// Every bubble at once, and nobody talks.
  void _endReveal() {
    _clock?.dispose();
    _clock = null;
    _revealed = true;
    _at = null;
  }

  /// Brings the reveal up to the panel on screen. A new panel starts its
  /// clock in the frame it first shows.
  void _syncReveal({required bool animated, required bool reduced}) {
    if (_revealOf != _step) {
      _clock?.dispose();
      _clock = null;
      _revealOf = _step;
      final step = _step;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _recordLastPanel(step),
      );
      final lines = [
        for (final line in _currentPanel.lines)
          if (line.speaker != PanelFallback.narrator) line,
      ];
      _spokenCount = lines.length;
      _turns = animated ? PanelTurns(_currentPanel.lines, _turnTimings) : null;
      _revealed = reduced || lines.isEmpty;
      if (_revealed) {
        _at = null;
        return;
      }
      _at = _turnsAt(Duration.zero);
      _clock = AnimationController(vsync: this, duration: _revealEnd)
        ..addListener(_tick)
        ..forward();
    } else if (reduced && _clock != null) {
      // Reduced motion turned on mid-reveal.
      _endReveal();
    }
  }

  Duration get _revealEnd =>
      _turns?.end ?? _lead + _stagger * (_spokenCount - 1);

  /// Where the reveal is at [elapsed]: an animated panel's turns, else one
  /// bubble every [_stagger] after the panel has slid in.
  TurnsAt _turnsAt(Duration elapsed) {
    if (_turns case final turns?) return turns.at(elapsed);
    final shown = elapsed < _lead
        ? 0
        : (1 + (elapsed - _lead).inMilliseconds ~/ _stagger.inMilliseconds)
              .clamp(0, _spokenCount);
    return TurnsAt(
      shown: shown,
      talking: null,
      lastStarted: shown >= _spokenCount,
    );
  }

  /// Rebuilds only when the reveal moves on, not every frame.
  void _tick() {
    final clock = _clock;
    if (clock == null) return;
    // A completed controller has already cleared its elapsed time when it
    // notifies, so its last tick is the end, not the start.
    final elapsed = clock.isCompleted
        ? _revealEnd
        : clock.lastElapsedDuration ?? Duration.zero;
    final at = _turnsAt(elapsed);
    if (at != _at) setState(() => _at = at);
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  // ---- sharing ----

  String _speakerName(AppLocalizations l10n, String driver, String speaker) =>
      speaker == ScenePlayer.driver ? driver : l10n.sceneSpeaker(speaker);

  Future<void> _share() async {
    if (_busyOrGone) return;
    _sharing = true;
    final l10n = AppLocalizations.of(context);
    try {
      // Everything read from `ref` and the tree before the first await.
      final gateway = ref.read(shareGatewayProvider);
      final scene = _currentScene;
      final panel = _currentPanel;
      final fileName = 'wassal_scene_${scene.sceneId}_${_panel + 1}.png';
      final box = _shareButton.currentContext?.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await _loadPictures(panel);
      if (!mounted) return;
      final png = await renderOffscreenPng(
        context,
        ScenePanelShare(
          panel: panel,
          speakerName: (speaker) => shareSpeakerName(l10n, speaker),
        ),
        ScenePanelShare.size,
      );
      // The player left while it was drawn: no sheet over another screen.
      if (!mounted) return;
      // M15: share {kind: scene}
      await gateway.shareImage(
        png,
        fileName: fileName,
        text: l10n.shareSceneText,
        origin: origin,
      );
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'story'),
      );
      if (mounted) showAppToast(context, l10n.shareFailed);
    } finally {
      _sharing = false;
    }
  }

  bool get _busyOrGone => _sharing || _leaving;

  /// Loads the panel's SVGs as the picture will ask for them (its drawing,
  /// or the characters of its fallback), so its first frame finds them.
  Future<void> _loadPictures(Panel panel) {
    final loaders = <SvgAssetLoader>[
      if (PanelArt.assetFor(panel.art) case final asset?)
        SvgAssetLoader(asset)
      else
        for (final speaker in {
          for (final line in panel.lines)
            if (line.speaker != PanelFallback.narrator) line.speaker,
        })
          SvgAssetLoader(CharacterAvatar.path(speaker)),
    ];
    return Future.wait([
      for (final loader in loaders)
        svg.cache.putIfAbsent(
          loader.cacheKey(context),
          () => loader.loadBytes(context),
        ),
    ]);
  }

  // ---- building ----

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(contentSourceProvider);
    final sequence = _sequence ??= _resolve(content);
    if (sequence.isEmpty) {
      // An unknown scene, or nothing unlocked: on to `then`.
      WidgetsBinding.instance.addPostFrameCallback((_) => _leave());
      return const ColoredBox(color: ColorTokens.dashboardBg);
    }
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final driver = ref.watch(driverNameProvider);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final panel = _currentPanel;
    final animated =
        ref.watch(scenePanelsProvider).animates(PanelArt.artFor(panel.art)) &&
        !reduced;
    _syncReveal(animated: animated, reduced: reduced);
    final at = _revealed ? null : _at;
    final scene = _currentScene;
    final last = _lastPanel;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: SystemBars(
        top: ColorTokens.dashboardBg,
        bottom: ColorTokens.dashboardBg,
        child: Scaffold(
          backgroundColor: ColorTokens.dashboardBg,
          body: Padding(
            padding: EdgeInsets.fromLTRB(
              LayoutTokens.gutter,
              screenTopInset(context),
              LayoutTokens.gutter,
              _bottom,
            ),
            // The read order: the title, the panel, the dots, the actions,
            // then «تخطّى».
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  chapterLabel: l10n.sceneViewerChapterLabel(
                    numbers.integer(_currentChapter.order),
                  ),
                  title: scene.title.arEg,
                  skipLabel: l10n.sceneViewerSkip,
                  onSkip: () => unawaited(_exit()),
                ),
                const SizedBox(height: _gap),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: (constraints.maxHeight - _belowPanel).clamp(
                            0,
                            SceneViewerPage.panelHeight,
                          ),
                          child: Semantics(
                            sortKey: const OrdinalSortKey(1),
                            container: true,
                            button: !last,
                            label: last ? null : l10n.sceneViewerNextPanelA11y,
                            onTap: last ? null : _tapPanel,
                            child: GestureDetector(
                              key: SceneViewerPage.panelKey,
                              behavior: HitTestBehavior.opaque,
                              // The panel's one semantics node is above.
                              excludeFromSemantics: true,
                              onTap: _tapPanel,
                              child: PanelSwitcher(
                                index: _step,
                                child: ScenePanelView(
                                  key: ValueKey(_step),
                                  panel: panel,
                                  speakerName: (speaker) =>
                                      _speakerName(l10n, driver, speaker),
                                  animate: animated,
                                  talking: at?.talking,
                                  shown: at?.shown,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: _gap),
                        Semantics(
                          sortKey: const OrdinalSortKey(2),
                          child: PageDots(
                            count: scene.panels.length,
                            index: _panel,
                            label: l10n.introPageOf(
                              numbers.integer(_panel + 1),
                              numbers.integer(scene.panels.length),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: _gap),
                // Only on the last panel, the space kept on the others.
                SizedBox(
                  height: SceneViewerPage.actionsHeight,
                  child: last
                      ? Semantics(
                          sortKey: const OrdinalSortKey(3),
                          child: _Actions(
                            shareKey: _shareButton,
                            shareLabel: l10n.sceneViewerShare,
                            continueLabel: l10n.sceneViewerContinue,
                            onShare: () => unawaited(_share()),
                            onContinue: () => unawaited(_continue()),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The scenes to play: that scene if it is unlocked, or the chapter's
  /// unlocked scenes in order; empty for neither.
  List<(Chapter, Scene)> _resolve(ContentSource content) {
    final progress = ref.read(playerProgressProvider);
    if (widget.sceneId case final id?) {
      return sequenceOfScene(content, progress, id);
    }
    return sequenceOfChapter(content, progress, widget.chapterId!);
  }
}

/// `SceneViewer` box 1: the chapter label over the scene's title at the start
/// side, «تخطّى» at the end.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.chapterLabel,
    required this.title,
    required this.skipLabel,
    required this.onSkip,
  });

  final String chapterLabel;
  final String title;
  final String skipLabel;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    // 44 high at the reference scale; a larger text scale grows it.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: LayoutTokens.touchMin),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              sortKey: const OrdinalSortKey(0),
              header: true,
              container: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapterLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeTokens.label.copyWith(
                      color: ColorTokens.dashboardMuted,
                    ),
                  ),
                  Text(
                    title,
                    key: SceneViewerPage.titleKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeTokens.displayS.copyWith(color: ColorTokens.sun),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            sortKey: const OrdinalSortKey(4),
            child: _SkipPill(
              key: SceneViewerPage.skipKey,
              label: skipLabel,
              onTap: onSkip,
            ),
          ),
        ],
      ),
    );
  }
}

/// `SceneViewer` box 3: «تخطّى», a 44-high `dashboard.raised` pill.
class _SkipPill extends StatelessWidget {
  const _SkipPill({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.pill);
    return Pressable(
      onTap: onTap,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        height: LayoutTokens.touchMin,
        padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ColorTokens.dashboardRaised,
          borderRadius: radius,
        ),
        child: Text(
          label,
          style: DesignExtras.skipLabel.copyWith(color: ColorTokens.paper),
        ),
      ),
    );
  }
}

/// `SceneViewer` boxes 19–21: «شارك» and «كمّل», 10 apart.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.shareKey,
    required this.shareLabel,
    required this.continueLabel,
    required this.onShare,
    required this.onContinue,
  });

  final GlobalKey shareKey;
  final String shareLabel;
  final String continueLabel;
  final VoidCallback onShare;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(SceneViewerPage._shareRadius);
    return Row(
      spacing: SceneViewerPage._actionsGap,
      children: [
        // As wide as its content, which the board measures 124; «كمّل»
        // takes the rest (224).
        KeyedSubtree(
          key: shareKey,
          child: Pressable(
            key: SceneViewerPage.shareKey,
            onTap: onShare,
            borderRadius: radius,
            semanticLabel: shareLabel,
            child: Container(
              height: SceneViewerPage.actionsHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: SceneViewerPage._shareSidePadding,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ColorTokens.dashboardRaised,
                borderRadius: radius,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: SpaceTokens.s8,
                children: [
                  const AppIcon(
                    'share',
                    size: SceneViewerPage._shareIcon,
                    color: ColorTokens.sun,
                  ),
                  Text(
                    shareLabel,
                    maxLines: 1,
                    style: DesignExtras.sceneShareLabel.copyWith(
                      color: ColorTokens.paper,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: AppButton.primary(
            key: SceneViewerPage.continueKey,
            label: continueLabel,
            onTap: onContinue,
          ),
        ),
      ],
    );
  }
}
