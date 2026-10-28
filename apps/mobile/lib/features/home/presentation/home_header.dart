// Home's header (specs/013-m08-home-result, contracts/home.md "The screen",
// HANDOFF `C-Home` block 1, `HomeStates` block 1): the profile, then the
// JENEHAT, BONAT and fuel pills, the fuel's countdown on trusted time.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/domain/fuel.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/pills.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/home/application/home_model.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/home/presentation/trusted_countdown.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// `C-Home` block 1's height, from the top inset to the scene card's gap.
const homeHeaderHeight = 58.0;

class HomeHeader extends ConsumerWidget {
  const HomeHeader({required this.model, super.key});

  final HomeModel model;

  static const profileKey = Key('HomeHeader.profile');
  static const coinsKey = Key('HomeHeader.coins');
  static const bonatKey = Key('HomeHeader.bonat');
  static const fuelKey = Key('HomeHeader.fuel');

  /// The pills' gap (HANDOFF: 6).
  static const double _pillGap = SpaceTokens.s6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final bonat = numbers.integer(model.bonat);
    // One line as drawn. When the pills and the profile don't fit side by
    // side (a narrow phone, large text, large balances), the pills go under
    // the profile rather than shrink or cut the name.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: homeHeaderHeight),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: SpaceTokens.s8,
        runSpacing: _pillGap,
        children: [
          _Profile(model: model, numbers: numbers),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CurrencyPill(
                key: coinsKey,
                kind: CurrencyKind.coin,
                value: numbers.integer(model.jenehat),
                semanticLabel: l10n.homeA11yCoins(
                  numbers.integer(model.jenehat),
                ),
              ),
              const SizedBox(width: _pillGap),
              if (model.offline)
                // The shop needs the network: not a link, and said so.
                Semantics(
                  button: true,
                  enabled: false,
                  label: l10n.homeA11yBonatOffline(bonat),
                  child: ExcludeSemantics(
                    child: CurrencyPill(
                      key: bonatKey,
                      kind: CurrencyKind.bonat,
                      value: bonat,
                    ),
                  ),
                )
              else
                CurrencyPill(
                  key: bonatKey,
                  kind: CurrencyKind.bonat,
                  value: bonat,
                  onTap: () => NavGuard.go(context, '/shop'),
                  semanticLabel: l10n.homeA11yBonat(bonat),
                ),
              const SizedBox(width: _pillGap),
              _FuelPill(model: model, numbers: numbers),
            ],
          ),
        ],
      ),
    );
  }
}

/// The driver: `CharacterAvatar('usta')` in the 48 `sun` circle, the name
/// (one line, 84 at most) and the level chip. Opens Settings.
class _Profile extends StatelessWidget {
  const _Profile({required this.model, required this.numbers});

  final HomeModel model;
  final NumberFormatter numbers;

  static const double _circle = 48;
  static const double _avatar = 46;
  static const double _nameMax = 84;
  static const double _gap = SpaceTokens.s8;
  static const double _lines = 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Pressable(
      key: HomeHeader.profileKey,
      onTap: () => NavGuard.push(context, '/settings'),
      semanticLabel: l10n.homeA11yProfile,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _gap,
        children: [
          Container(
            width: _circle,
            height: _circle,
            decoration: const BoxDecoration(
              color: ColorTokens.sun,
              shape: BoxShape.circle,
              boxShadow: [LipTokens.sun],
            ),
            alignment: Alignment.bottomCenter,
            child: const ClipOval(
              child: SizedBox.square(
                dimension: _avatar,
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: CharacterAvatar('usta'),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _lines,
            children: [
              // 84 as drawn, growing with the text, so only a long name is
              // cut short.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.textScalerOf(context).scale(_nameMax),
                ),
                child: Text(
                  model.driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: DesignExtras.homeName.copyWith(color: ColorTokens.ink),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: ColorTokens.paper,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpaceTokens.s8,
                  ),
                  child: Text(
                    l10n.homeLevelChip(numbers.integer(model.driverLevel)),
                    style: TypeTokens.label.copyWith(
                      color: ColorTokens.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The tank: «٤/٥» over the next liter's countdown; `danger.soft` when
/// empty; during a window, the window's time left. Opens the fuel sheet.
/// Its screen-reader label changes a minute at a time (research R11).
class _FuelPill extends StatelessWidget {
  const _FuelPill({required this.model, required this.numbers});

  final HomeModel model;
  final NumberFormatter numbers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fuel = model.fuel;
    final value = numbers.ratio(fuel.liters, fuel.max);
    final until = switch (model.fuelState) {
      HomeFuelState.unlimited => fuel.unlimitedUntilMs,
      _ => fuel.nextLiterAtMs,
    };
    Widget pill(String label) => CurrencyPill(
      key: HomeHeader.fuelKey,
      kind: CurrencyKind.fuel,
      value: value,
      empty: model.fuelState == HomeFuelState.empty,
      timerChild: until == null ? null : TrustedCountdown(untilMs: until),
      onTap: () => NavGuard.go(context, fuelSheetLocation),
      semanticLabel: label,
    );
    if (until == null) {
      return pill(
        l10n.homeA11yFuelFull(
          numbers.integer(fuel.liters),
          numbers.integer(fuel.max),
        ),
      );
    }
    return TrustedMinutes(
      untilMs: until,
      builder: (context, minutes) =>
          pill(_label(l10n, fuel, model.fuelState, minutes)),
    );
  }

  String _label(
    AppLocalizations l10n,
    FuelView fuel,
    HomeFuelState state,
    int minutes,
  ) {
    final n = numbers.integer(minutes);
    return switch (state) {
      HomeFuelState.empty => l10n.homeA11yFuelEmpty(minutes, n),
      HomeFuelState.unlimited => l10n.homeA11yFuelUnlimited(minutes, n),
      HomeFuelState.normal => l10n.homeA11yFuel(
        numbers.integer(fuel.liters),
        numbers.integer(fuel.max),
        minutes,
        n,
      ),
    };
  }
}
