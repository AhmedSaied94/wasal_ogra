import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/back_to_exit.dart';
import 'package:wassal/core/routing/new_dot_providers.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/theme/components/wassal_bottom_bar.dart';

/// The four tabs around their branch navigators. Tapping the current tab
/// returns that tab to its root.
///
/// The open tab never keeps its «new» dot: opening a tab, by the bar or by
/// a link, clears it (FR-016a).
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = navigationShell;
    final dots = [
      for (final section in tabSections) ref.watch(newDotProvider(section)),
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
        bottomNavigationBar: WassalBottomBar(
          currentIndex: shell.currentIndex,
          newDots: dots,
          onTap: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
        ),
      ),
    );
  }
}
