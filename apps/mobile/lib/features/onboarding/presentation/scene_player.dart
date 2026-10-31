import 'package:content_models/content_models.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/art/rive_scenes.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/core/theme/tokens/scene_turn_tokens.dart';
import 'package:wassal/features/onboarding/domain/panel_turns.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// How long the scenes' turns last (specs/012.5-m22-animated-scenes,
/// research R5).
final _turnTimings = TurnTimings(
  leadIn: SceneTurnTokens.leadIn,
  perLetter: SceneTurnTokens.perLetter,
  min: SceneTurnTokens.min,
  max: SceneTurnTokens.max,
  pause: SceneTurnTokens.pause,
);

/// Plays one scene as a comic, built to the `Intro` artboard
/// (specs/012-m07-onboarding/contracts/scenes.md "The player"): the
/// chapter's [title] and «تخطّى», one [ComicPanel] per panel, the page dots
/// and «يلا». «يلا» shows the next panel; on the last one, «تخطّى» and back
/// call [onFinished], once.
///
/// A panel that animates plays its lines in turn
/// (specs/012.5-m22-animated-scenes, contracts/scene-turns.md): each
/// speaker's bubble pops up and they talk for their turn. «يلا» before the
/// last turn has started shows the rest; the next «يلا» moves on.
class ScenePlayer extends ConsumerStatefulWidget {
  const ScenePlayer({
    required this.title,
    required this.scene,
    required this.driverName,
    required this.onFinished,
    super.key,
  });

  final String title;
  final Scene scene;

  /// The `usta` speaker's label: the player's name.
  final String driverName;
  final VoidCallback onFinished;

  static const skipKey = Key('ScenePlayer.skip');
  static const nextKey = Key('ScenePlayer.next');
  static const panelKey = Key('ScenePlayer.panel');

  /// `Intro` box 3: the panel's height on the reference frame. Shorter
  /// screens give it less.
  static const double panelHeight = 540;

  /// The speaker whose line is the panel's caption (scenes.md "Captions").
  static const narrator = PanelFallback.narrator;
  static const driver = 'usta';

  @override
  ConsumerState<ScenePlayer> createState() => _ScenePlayerState();
}

class _ScenePlayerState extends ConsumerState<ScenePlayer>
    with TickerProviderStateMixin {
  int _index = 0;
  bool _finished = false;

  /// The panel [_turns] and [_clock] belong to.
  int? _turnsOf;
  PanelTurns? _turns;

  /// The turns' clock, while they play; one per animated panel.
  AnimationController? _clock;

  /// Where the turns are, once per change.
  TurnsAt? _at;

  /// The panel shows every bubble and nobody talks: it showed still, has no
  /// turns, or «يلا» or the end of the scene stopped them.
  bool _done = false;

  /// `Intro`: the header, panel, dots and CTA are 16 apart.
  static const double _gap = 16;

  /// `Intro`: the screen's padding, 36 16 28; the top follows the phone.
  static const double _bottom = 28;

  /// Under the panel: the gap, the dots, and at least a gap above «يلا».
  static const double _belowPanel = _gap + _dots + _gap;
  static const double _dots = 10;

  List<Panel> get _panels => widget.scene.panels;

  void _finish() {
    if (_finished) return;
    _finished = true;
    // Nothing keeps talking while the scene goes.
    setState(_endTurns);
    widget.onFinished();
  }

  void _next() {
    if (_finished) return;
    if (_clock != null && !(_at?.lastStarted ?? true)) {
      setState(_endTurns);
    } else if (_index + 1 < _panels.length) {
      setState(() => _index++);
    } else {
      _finish();
    }
  }

  /// Every bubble at once, and nobody talks.
  void _endTurns() {
    _clock?.dispose();
    _clock = null;
    _done = true;
  }

  /// Brings the turns up to the panel on screen and whether it [animated].
  /// A new panel starts its clock in the frame it first shows.
  void _syncTurns({required bool animated}) {
    if (_turnsOf != _index) {
      _clock?.dispose();
      _clock = null;
      _turnsOf = _index;
      final turns = PanelTurns(_panels[_index].lines, _turnTimings);
      _turns = turns;
      _at = turns.at(Duration.zero);
      _done = !animated || turns.turns.isEmpty;
      if (!_done) {
        _clock = AnimationController(vsync: this, duration: turns.end)
          ..addListener(_tick)
          ..forward();
      }
    } else if (!animated && _clock != null) {
      // Reduced motion turned on mid-turn.
      _endTurns();
    }
  }

  /// Rebuilds only when the turns move on, not every frame.
  void _tick() {
    final (clock, turns) = (_clock, _turns);
    if (clock == null || turns == null) return;
    // A completed controller has already cleared its elapsed time when it
    // notifies, so its last tick is the turns' end, not their start.
    final elapsed = clock.isCompleted
        ? turns.end
        : clock.lastElapsedDuration ?? Duration.zero;
    final at = turns.at(elapsed);
    if (at != _at) setState(() => _at = at);
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final count = _panels.length;
    final animated =
        ref
            .watch(scenePanelsProvider)
            .animates(PanelArt.artFor(_panels[_index].art)) &&
        !MediaQuery.disableAnimationsOf(context);
    _syncTurns(animated: animated);
    final turns = _done ? null : _at;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
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
            // The read order (scenes.md): title, the panel, the dots,
            // «يلا», then «تخطّى».
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: LayoutTokens.touchMin,
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          sortKey: const OrdinalSortKey(0),
                          header: true,
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TypeTokens.displayS.copyWith(
                              color: ColorTokens.sun,
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        sortKey: const OrdinalSortKey(4),
                        child: _SkipPill(
                          key: ScenePlayer.skipKey,
                          label: l10n.introSkip,
                          onTap: _finish,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: _gap),
                // The panel takes its 540 first; a shorter screen takes
                // the difference from the panel, keeping the dots and CTA.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: (constraints.maxHeight - _belowPanel).clamp(
                            0,
                            ScenePlayer.panelHeight,
                          ),
                          child: Semantics(
                            sortKey: const OrdinalSortKey(1),
                            child: _Talking(
                              index: _index,
                              talking: turns?.talking,
                              child: PanelSwitcher(
                                key: ScenePlayer.panelKey,
                                index: _index,
                                child: _panel(
                                  l10n,
                                  _panels[_index],
                                  animated: animated,
                                  shown: turns?.shown,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: _gap),
                        Semantics(
                          sortKey: const OrdinalSortKey(2),
                          child: PageDots(
                            count: count,
                            index: _index,
                            label: l10n.introPageOf(
                              numbers.integer(_index + 1),
                              numbers.integer(count),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  sortKey: const OrdinalSortKey(3),
                  child: AppButton.primary(
                    key: ScenePlayer.nextKey,
                    label: l10n.introNext,
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(
    AppLocalizations l10n,
    Panel panel, {
    required bool animated,
    required int? shown,
  }) {
    String? caption;
    final lines = <(String, String)>[];
    for (final line in panel.lines) {
      if (line.speaker == ScenePlayer.narrator) {
        caption ??= line.text.arEg;
      } else {
        lines.add((_speaker(l10n, line.speaker), line.text.arEg));
      }
    }
    final speakers = [for (final line in panel.lines) line.speaker];
    return ComicPanel(
      key: ValueKey(_index),
      art: _PanelArtInTurn(
        index: _index,
        slug: panel.art,
        speakers: speakers,
        current: speakers.firstWhere(
          (s) => s != ScenePlayer.narrator,
          orElse: () => ScenePlayer.narrator,
        ),
        animate: animated,
      ),
      caption: caption,
      lines: lines,
      shown: shown,
    );
  }

  String _speaker(AppLocalizations l10n, String speaker) =>
      speaker == ScenePlayer.driver
      ? widget.driverName
      : l10n.sceneSpeaker(speaker);
}

/// Who talks in the panel at [index], the one on screen. A panel on its way
/// out talks no more (spec FR-015).
class _Talking extends InheritedWidget {
  const _Talking({
    required this.index,
    required this.talking,
    required super.child,
  });

  final int index;
  final String? talking;

  static String? of(BuildContext context, int index) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Talking>();
    return scope != null && scope.index == index ? scope.talking : null;
  }

  @override
  bool updateShouldNotify(_Talking oldWidget) =>
      oldWidget.index != index || oldWidget.talking != talking;
}

/// The panel at [index]'s art, its speaker talking while it is on screen.
class _PanelArtInTurn extends StatelessWidget {
  const _PanelArtInTurn({
    required this.index,
    required this.slug,
    required this.speakers,
    required this.current,
    required this.animate,
  });

  final int index;
  final String slug;
  final List<String> speakers;
  final String current;
  final bool animate;

  @override
  Widget build(BuildContext context) => PanelArt(
    slug: slug,
    speakers: speakers,
    current: current,
    animate: animate,
    talking: _Talking.of(context, index),
  );
}

/// Changes panels: a slide and fade within `sheetIn`, the new bubble
/// popping in; under reduced motion a fade of at most 150 ms. The story
/// viewer (specs/015-m10-apartment-story) changes panels the same way: its
/// [child] is keyed `ValueKey(index)`.
class PanelSwitcher extends StatelessWidget {
  const PanelSwitcher({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  /// How far a panel slides, as a share of its width.
  static const double _slide = 0.12;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduced ? DesignExtras.panelFadeReduced : MotionTokens.sheetIn,
      switchInCurve: MotionTokens.sheetInCurve,
      switchOutCurve: MotionTokens.sheetInCurve,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (reduced) return fade;
        // The next panel comes in from the reading side's end.
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final incoming = child.key == ValueKey(index);
        final from = Offset((rtl ? -_slide : _slide) * (incoming ? 1 : -1), 0);
        return SlideTransition(
          position: Tween(begin: from, end: Offset.zero).animate(animation),
          child: fade,
        );
      },
      child: child,
    );
  }
}

/// `Intro` box 2: «تخطّى», a 44-high `dashboard.raised` pill.
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
