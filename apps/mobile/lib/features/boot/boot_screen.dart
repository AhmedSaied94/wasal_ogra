import 'dart:async';
import 'dart:math' as math;

import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/bootstrap/boot_progress.dart';
import 'package:wassal/bootstrap/startup.dart';
import 'package:wassal/core/account/account_providers.dart';
import 'package:wassal/core/account/account_service.dart';
import 'package:wassal/core/account/domain/account.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/components/system_bars.dart';
import 'package:wassal/core/theme/components/vehicle_sprite.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/trip/trip_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The cloud's two bumps (`Loading` block 0), in points.
const _cloudBigBump = 18.0;
const _cloudSmallBump = 15.0;

/// The lines the loading screen picks from, one per launch (research R6).
/// More are copy for the owner.
List<String> loadingLines(AppLocalizations l10n) => [l10n.loadingLine1];

/// The first Flutter frame, the `Loading` artboard (HANDOFF `Loading`,
/// research R6): on `sun` like the native splash, so there is no flash
/// between them (M03 FR-012). The road bar follows the boot steps, a failure
/// offers M03's retry, and it hands over once startup completes and, on a
/// first open, the account's work is done or [firstOpenWait] has passed
/// (specs/011-m06-identity-sync, research R6).
class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  static const vehicleKey = Key('BootScreen.vehicle');
  static const vehicleIn = DesignExtras.loadingVehicleIn;

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen>
    with SingleTickerProviderStateMixin {
  bool _handedOver = false;

  /// Which loading line this launch shows.
  final int _pick = math.Random().nextInt(1 << 16);

  late final _drive = AnimationController(
    vsync: this,
    duration: BootScreen.vehicleIn,
  );
  late final _driveCurve = CurvedAnimation(
    parent: _drive,
    curve: DesignExtras.loadingVehicleCurve,
  );
  bool _driveStarted = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(appStartupProvider, (_, next) {
      if (next is AsyncData<void>) unawaited(_handOver());
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_driveStarted) return;
    _driveStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _drive.value = 1;
    } else {
      _drive.forward().ignore();
    }
  }

  @override
  void dispose() {
    _driveCurve.dispose();
    _drive.dispose();
    super.dispose();
  }

  /// Back into the trip a kill interrupted
  /// (specs/008-m02-trip-screen/contracts/trip-controller.md "Launch"), or
  /// where the first session says: its next screen, or الموقف
  /// (specs/012-m07-onboarding/contracts/first-session.md "Boot").
  Future<void> _handOver() async {
    if (_handedOver) return;
    _handedOver = true;
    // Startup opened both; awaiting them also leaves initState, where
    // navigating would rebuild the router mid-frame.
    final economy = await ref.read(economyProvider.future);
    await ref.read(appDatabaseProvider.future);
    if (!mounted) return;
    final outcome = await _waitForFirstOpen();
    if (!mounted) return;
    ref.read(bootProgressProvider.notifier).markDone(BootStep.account);
    final unfinished = economy.view.unfinished;
    // Stale records go before a trip can open.
    await ref.read(tripRecordsProvider).deleteAllExcept(unfinished?.startTxn);
    if (!mounted) return;
    // Past this, a returning player's state waits for the sync, off the
    // trip screen (R6). The account never blocks play.
    try {
      (await ref.read(accountServiceProvider.future)).handOver();
    } on Object {
      // No account service: nothing can restore past the hand-over either.
    }
    if (!mounted) return;
    // The flags load before any redirect reads them. A restored player has
    // seen the opening, on another phone.
    final flags = ref.read(firstSessionFlagsProvider.notifier);
    await ref.read(firstSessionFlagsProvider.future);
    if (outcome == FirstOpenOutcome.restored) await flags.markOpeningDone();
    if (!mounted) return;
    context.go(
      unfinished == null
          ? ref.read(firstSessionProvider).launchTarget(outcome)
          : '/trip/${unfinished.tripId}',
    );
  }

  /// The first open's outcome, up to [firstOpenWait]: at once on a later
  /// launch, or with no network. The work goes on past it.
  Future<FirstOpenOutcome> _waitForFirstOpen() async {
    try {
      return await ref
          .read(firstOpenOutcomeProvider.future)
          .timeout(firstOpenWait, onTimeout: () => FirstOpenOutcome.timedOut);
    } on Object {
      // A failure of the account's work never blocks play.
      return FirstOpenOutcome.timedOut;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final startup = ref.watch(appStartupProvider);
    final failed = startup.hasError && !startup.isLoading;
    final lines = loadingLines(l10n);
    return SystemBars(
      top: ColorTokens.sun,
      bottom: ColorTokens.sun,
      child: Scaffold(
        backgroundColor: ColorTokens.sun,
        body: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _Backdrop())),
            LayoutBuilder(
              builder: (context, constraints) {
                // The board's 844 points; shorter screens close the gaps.
                final scale = math.min(1.0, constraints.maxHeight / _frame);
                return CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        children: [
                          SizedBox(height: _wordmarkTop * scale),
                          Text(
                            l10n.appName,
                            textAlign: TextAlign.center,
                            style: DesignExtras.loadingWordmark.copyWith(
                              color: ColorTokens.ink,
                              shadows: const [
                                DesignExtras.loadingWordmarkShadow,
                              ],
                            ),
                          ),
                          const SizedBox(height: _taglineGap),
                          Text(
                            l10n.loadingTagline,
                            textAlign: TextAlign.center,
                            style: DesignExtras.loadingTagline.copyWith(
                              color: ColorTokens.ink2,
                            ),
                          ),
                          SizedBox(height: _vehicleGap * scale),
                          AnimatedBuilder(
                            animation: _driveCurve,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(
                                (1 - _driveCurve.value) * constraints.maxWidth,
                                0,
                              ),
                              child: child,
                            ),
                            child: _Vehicle(sign: l10n.destHome),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: _barInset,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: _lineGap,
                              children: [
                                ProgressBar.road(
                                  value: ref.watch(bootProgressProvider).value,
                                  semanticLabel: l10n.loadingProgressLabel,
                                ),
                                if (failed)
                                  InlineAlert(
                                    icon: 'warning',
                                    message: l10n.bootErrorMessage,
                                    action: l10n.bootRetry,
                                    onAction: () => retryAppStartup(ref),
                                  )
                                else
                                  Center(
                                    child: Text(
                                      lines[_pick % lines.length],
                                      textAlign: TextAlign.center,
                                      style: DesignExtras.loadingLine.copyWith(
                                        color: ColorTokens.ink,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: _barBottom * scale),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // HANDOFF `Loading` blocks 1 – 5 on the 390×844 board.
  static const double _frame = 844;
  static const double _wordmarkTop = 210;
  static const double _taglineGap = 6;
  static const double _vehicleGap = 40;
  static const double _barInset = 45;
  static const double _lineGap = 14;
  static const double _barBottom = 118;
}

/// The vehicle with its roof sign (block 3): `wassal.riv`'s old microbus
/// driving, or without it the design's drawing, 300×170; and the sign
/// «الموقف» laid over either in the drawing's own units, so its text comes
/// from the ARB.
class _Vehicle extends StatelessWidget {
  const _Vehicle({required this.sign});

  final String sign;

  static const _asset = 'assets/illustrations/screens/Loading_01.svg';
  static const Size _size = Size(300, 170);

  /// The drawing's view box, and the sign in it.
  static const Size _art = Size(358, 210);
  static const Rect _sign = Rect.fromLTWH(114, 4, 96, 26);

  /// Where the Rive microbus covers the drawn one, in the drawing's units:
  /// body, wheels and shadow, x 30 to 326, down to y 205.
  static const Rect _bus = Rect.fromLTWH(30, 17, 296, 188);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    key: BootScreen.vehicleKey,
    size: _size,
    child: FittedBox(
      child: SizedBox.fromSize(
        size: _art,
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: _bus,
              child: VehicleSprite(
                vehicle: VehicleId.microOld,
                driving: true,
                fallback: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -_bus.left,
                      top: -_bus.top,
                      width: _art.width,
                      height: _art.height,
                      child: SvgPicture.asset(
                        _asset,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fromRect(
              rect: _sign,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ColorTokens.ink,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      sign,
                      style: DesignExtras.loadingSign.copyWith(
                        color: ColorTokens.sun,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Block 0: the two `sun.glow` circles, one by the top-end corner and one
/// by the bottom-start, and the small cloud.
class _Backdrop extends CustomPainter {
  const _Backdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()..color = ColorTokens.sunGlow;
    canvas
      ..drawCircle(Offset(size.width - 60, 120), 70, glow)
      ..drawCircle(Offset(40, size.height - 144), 110, glow);
    final cloud = Path()
      ..moveTo(44, 160)
      ..arcToPoint(
        const Offset(78, 152),
        radius: const Radius.circular(_cloudBigBump),
      )
      ..arcToPoint(
        const Offset(104, 162),
        radius: const Radius.circular(_cloudSmallBump),
      )
      ..lineTo(44, 162)
      ..close();
    canvas.drawPath(
      cloud,
      Paint()..color = ColorTokens.paper.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) => false;
}
