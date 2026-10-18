import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The first Flutter frame: شمس like the native splash, so there is no flash
/// between them (FR-012). Hands over to الموقف once startup completes.
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
      if (next is AsyncData<void>) _handOver();
    }, fireImmediately: true);
  }

  void _handOver() {
    if (_handedOver) return;
    _handedOver = true;
    // Navigating from initState or a build would rebuild the router mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/home');
    });
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
