import 'package:content_models/content_models.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/panel_art.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/components/story.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Plays one scene as a comic, built to the `Intro` artboard
/// (specs/012-m07-onboarding/contracts/scenes.md "The player"): the
/// chapter's [title] and «تخطّى», one [ComicPanel] per panel, the page dots
/// and «يلا». «يلا» shows the next panel; on the last one, «تخطّى» and back
/// call [onFinished], once.
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

class _ScenePlayerState extends ConsumerState<ScenePlayer> {
  int _index = 0;
  bool _finished = false;

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
    widget.onFinished();
  }

  void _next() {
    if (_finished) return;
    if (_index + 1 < _panels.length) {
      setState(() => _index++);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final count = _panels.length;
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
                            child: _PanelSwitcher(
                              key: ScenePlayer.panelKey,
                              index: _index,
                              child: _panel(l10n, _panels[_index]),
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

  Widget _panel(AppLocalizations l10n, Panel panel) {
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
      art: PanelArt(
        slug: panel.art,
        speakers: speakers,
        current: speakers.firstWhere(
          (s) => s != ScenePlayer.narrator,
          orElse: () => ScenePlayer.narrator,
        ),
      ),
      caption: caption,
      lines: lines,
    );
  }

  String _speaker(AppLocalizations l10n, String speaker) =>
      speaker == ScenePlayer.driver
      ? widget.driverName
      : l10n.sceneSpeaker(speaker);
}

/// Changes panels: a slide and fade within `sheetIn`, the new bubble
/// popping in; under reduced motion a fade of at most 150 ms.
class _PanelSwitcher extends StatelessWidget {
  const _PanelSwitcher({required this.index, required this.child, super.key});

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
