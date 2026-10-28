// A late restore (specs/012-m07-onboarding/contracts/first-session.md "A
// late restore"): a returning player's state, taken by the sync after boot
// handed over, moves a player still in the opening or on the Name card to
// Home. Anywhere else the next navigation reads the new facts. A name
// confirmed here before it stays, as the sync replays the pending
// operations over the server's state (FR-005).
import 'package:go_router/go_router.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

final class FirstSessionLifecycle {
  FirstSessionLifecycle({
    required this._router,
    required this._flags,
    required this._view,
  });

  final GoRouter _router;
  final FirstSessionFlagsNotifier _flags;
  final EconomyView Function() _view;

  static final Set<String> _opening = {
    destinationNamed(RouteNames.onboardingIntro).path!,
    destinationNamed(RouteNames.onboardingName).path!,
  };

  bool get _inOpening => _opening.contains(_router.state.uri.path);

  /// The sync took a returning player's state.
  Future<void> restored() async {
    if (!_inOpening) return;
    final view = _view();
    if (view.displayName == null && view.progress.isEmpty) return;
    await _flags.markOpeningDone();
    // The player may have left the opening meanwhile.
    if (_inOpening) _router.go(destinationNamed(RouteNames.home).path!);
  }
}
