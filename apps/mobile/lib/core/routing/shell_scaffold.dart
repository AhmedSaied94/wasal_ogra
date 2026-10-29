import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/back_to_exit.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/nav.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';

/// The four tabs around their branch navigators, over the `BottomNav`.
/// Tapping the current tab returns that tab to its root.
///
/// The open tab never keeps its «new» dot: opening a tab, by the bar or by
/// a link, clears it (M03 FR-016a).
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = navigationShell;
    final dots = [
      for (final section in tabSections) ref.watch(newDotProvider(section)),
    ];
    // The shop needs the network; every other tab works without it
    // (specs/013-m08-home-result FR-014).
    final offline = ref.watch(
      serverStatusProvider.select((status) => status.reach == Reach.offline),
    );
    final disabled = [
      for (final section in tabSections) offline && section == Section.shop,
    ];
    final open = tabSections[shell.currentIndex];
    if (dots[shell.currentIndex]) {
      // Providers cannot change while widgets build; clear after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(newDotProvider(open).notifier).clear();
      });
    }
    return BackToExit(
      navigationShell: shell,
      child: Scaffold(
        body: shell,
        bottomNavigationBar: BottomNav(
          currentIndex: shell.currentIndex,
          newDots: dots,
          disabled: disabled,
          // A tab reopens where it was left, or at its root when tapped
          // again (M03). Lines always opens at its root, so a card left for
          // a trip isn't rebuilt there (specs/014-m09-lines-vehicles R5).
          onTap: (index) => shell.goBranch(
            index,
            initialLocation:
                index == shell.currentIndex ||
                tabSections[index] == Section.lines,
          ),
        ),
      ),
    );
  }
}

/// The tabs' branch navigators, cross-fading over 150 ms when the tab
/// changes (HANDOFF §6.5), with none under reduced motion. As in an
/// `IndexedStack`, only the open tab (and the one fading out) is on stage;
/// the others keep their state offstage. The branch navigators carry global
/// keys, so the cross-fade keeps one copy of each rather than switching
/// widgets.
class TabCrossFade extends StatefulWidget {
  const TabCrossFade({
    required this.currentIndex,
    required this.children,
    super.key,
  });

  final int currentIndex;
  final List<Widget> children;

  static const duration = DesignExtras.tabFade;

  @override
  State<TabCrossFade> createState() => _TabCrossFadeState();
}

class _TabCrossFadeState extends State<TabCrossFade>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: TabCrossFade.duration,
    value: 1,
  )..addStatusListener(_onStatus);
  late final _fadeOut = ReverseAnimation(_fade);

  /// The tab fading out, while it does.
  int? _leaving;

  void _onStatus(AnimationStatus status) {
    if (status.isCompleted && _leaving != null) {
      setState(() => _leaving = null);
    }
  }

  @override
  void didUpdateWidget(TabCrossFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _leaving = null;
      _fade.value = 1;
      return;
    }
    _leaving = oldWidget.currentIndex;
    _fade.forward(from: 0).ignore();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final (i, child) in widget.children.indexed)
        _branch(child, open: i == widget.currentIndex, leaving: i == _leaving),
    ],
  );

  /// Every branch keeps the same wrappers, so switching tabs never rebuilds
  /// a navigator from scratch.
  Widget _branch(Widget child, {required bool open, required bool leaving}) =>
      Offstage(
        offstage: !open && !leaving,
        child: TickerMode(
          enabled: open || leaving,
          child: IgnorePointer(
            ignoring: !open,
            child: ExcludeSemantics(
              excluding: !open,
              child: FadeTransition(
                opacity: open
                    ? _fade
                    : leaving
                    ? _fadeOut
                    : kAlwaysCompleteAnimation,
                child: child,
              ),
            ),
          ),
        ),
      );
}
