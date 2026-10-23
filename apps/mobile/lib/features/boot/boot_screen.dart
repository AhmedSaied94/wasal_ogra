import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/features/trip/trip_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The first Flutter frame: شمس like the native splash, so there is no flash
/// between them (FR-012). Hands over once startup completes.
class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen> {
  bool _handedOver = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(appStartupProvider, (_, next) {
      if (next is AsyncData<void>) unawaited(_handOver());
    }, fireImmediately: true);
  }

  /// To الموقف, or back into the trip a kill interrupted
  /// (specs/008-m02-trip-screen/contracts/trip-controller.md "Launch").
  Future<void> _handOver() async {
    if (_handedOver) return;
    _handedOver = true;
    // Startup opened both; awaiting them also leaves initState, where
    // navigating would rebuild the router mid-frame.
    final economy = await ref.read(economyProvider.future);
    await ref.read(appDatabaseProvider.future);
    // The character too, so the first trip doesn't open with the stand-in.
    await ref.read(passengerRiveProvider.future);
    if (!mounted) return;
    final unfinished = economy.view.unfinished;
    // Stale records go before a trip can open.
    await ref.read(tripRecordsProvider).deleteAllExcept(unfinished?.startTxn);
    if (!mounted) return;
    context.go(unfinished == null ? '/home' : '/trip/${unfinished.tripId}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final startup = ref.watch(appStartupProvider);
    final failed = startup.hasError && !startup.isLoading;
    return Scaffold(
      backgroundColor: tokens.shams,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SpaceTokens.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.appName,
                  textAlign: TextAlign.center,
                  style: TypeTokens.display.copyWith(color: tokens.hibr),
                ),
                if (failed) ...[
                  const SizedBox(height: SpaceTokens.xl),
                  Text(
                    l10n.bootErrorMessage,
                    textAlign: TextAlign.center,
                    style: TypeTokens.body.copyWith(color: tokens.hibr),
                  ),
                  const SizedBox(height: SpaceTokens.l),
                  PrimaryButton(
                    label: l10n.bootRetry,
                    onPressed: () => retryAppStartup(ref),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
