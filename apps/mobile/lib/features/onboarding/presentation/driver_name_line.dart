import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';

/// The driver's name over the playtest Home's tools (dev and staging), the
/// one place the name shows until M08 builds Home (specs/012-m07-onboarding/
/// contracts/name.md "The name shown").
class DriverNameLine extends ConsumerWidget {
  const DriverNameLine({super.key});

  static const nameKey = Key('DriverNameLine.name');

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    ref.watch(driverNameProvider),
    key: nameKey,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TypeTokens.displayS.copyWith(color: ColorTokens.ink),
  );
}
