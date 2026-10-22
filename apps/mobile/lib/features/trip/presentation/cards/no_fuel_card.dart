// The start refused for an empty tank: when the next free liter comes, on
// trusted time, and the way to the fuel sheet or back to the stand.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/theme/components/primary_button.dart';
import 'package:wassal/core/theme/components/secondary_button.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/features/trip/presentation/cards/trip_card.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

class NoFuelCard extends ConsumerStatefulWidget {
  const NoFuelCard({
    required this.nextLiterAtMs,
    required this.onFuel,
    required this.onHome,
    super.key,
  });

  final int? nextLiterAtMs;
  final VoidCallback onFuel;
  final VoidCallback onHome;

  @override
  ConsumerState<NoFuelCard> createState() => _NoFuelCardState();
}

class _NoFuelCardState extends ConsumerState<NoFuelCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.nextLiterAtMs != null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final next = widget.nextLiterAtMs;
    final now = ref.watch(trustedClockProvider).value?.nowMs();
    return TripCard(
      title: l10n.tripNoFuelTitle,
      children: [
        if (next != null && now != null)
          CardText(
            l10n.tripNoFuelNext(
              numbers.countdown(Duration(milliseconds: next - now)),
            ),
          ),
        PrimaryButton(label: l10n.tripNoFuelShop, onPressed: widget.onFuel),
        const SizedBox(height: SpaceTokens.m),
        SecondaryButton(label: l10n.tripNoFuelHome, onPressed: widget.onHome),
      ],
    );
  }
}
