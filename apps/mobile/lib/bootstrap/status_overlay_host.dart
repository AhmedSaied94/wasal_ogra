// The update card over every screen but the trip (specs/011-m06-identity-
// sync, contracts/server-states.md "Placements", research R18).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/platform/store_launcher.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/core/sync/server_status.dart';
import 'package:wassal/core/sync/sync_lifecycle.dart' show isTripRoute;
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// Pushes the update card on the root navigator, above [child] (the
/// router's), while an update is due. Neither the phone's back nor a tap
/// outside closes it, and the scrim takes every touch beneath it: a forced
/// one stays until the next launch, an optional one until «بعدين». It
/// waits while the trip or the boot screen shows, and shows on leaving
/// them.
class StatusOverlayHost extends ConsumerStatefulWidget {
  const StatusOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StatusOverlayHost> createState() => _StatusOverlayHostState();
}

class _StatusOverlayHostState extends ConsumerState<StatusOverlayHost> {
  static final _bootPath = destinationNamed(RouteNames.boot).path!;

  late final GoRouter _router;
  Route<void>? _card;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider);
    _router.routerDelegate.addListener(_schedule);
    ref.listenManual(serverStatusProvider, (previous, next) {
      if (previous?.update != next.update) _schedule();
    });
    _schedule();
  }

  /// After the frame: by then the navigator holds the router's new pages,
  /// so the card goes above them, not above a page that is leaving.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _place();
      })
      ..ensureVisualUpdate();
  }

  void _place() {
    final navigator = _router.routerDelegate.navigatorKey.currentState;
    if (navigator == null) return;
    // A navigation removes it with the page beneath it.
    if (_card case final card? when !card.isActive) _card = null;
    final card = _card;
    if (ref.read(serverStatusProvider).update is NoUpdate) {
      if (card == null) return;
      _card = null;
      card.isCurrent ? navigator.pop() : navigator.removeRoute(card);
      return;
    }
    final path = _router.state.uri.path;
    if (card != null || isTripRoute(path) || path == _bootPath) return;
    final route = _card = appDialogRoute<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => const _UpdateCard(),
    );
    unawaited(navigator.push(route));
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// `States` box 26, labelled by its title. The store button only where
/// there is a listing; «بعدين» only when the update is optional.
class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  static const double _picture = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(storeLauncherProvider);
    final optional = ref.watch(serverStatusProvider).update is OptionalUpdate;
    return AppDialog(
      semanticLabel: l10n.updateTitle,
      padding: EdgeInsets.zero,
      child: StatusCard.update(
        title: l10n.updateTitle,
        message: l10n.updateMessage,
        picture: const AppIcon('upgrade_cassette', size: _picture),
        actions: [
          if (store.hasListing)
            AppButton.primary(
              label: l10n.updateCta,
              size: AppButtonSize.compact,
              onTap: () => unawaited(store.openListing()),
            ),
          if (optional)
            AppButton.tertiary(
              label: l10n.updateLater,
              onTap: () =>
                  unawaited(ref.read(serverStatusProvider.notifier).dismiss()),
            ),
        ],
      ),
    );
  }
}
