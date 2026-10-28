// `settings_update` (specs/012-m07-onboarding/contracts/name.md "The
// operation", research R7, R8): the driver's name, checked by the phone's
// name rules, the one check the phone and the economy share. No currency or
// fuel changes, and it stays valid in every fold: a refusal is the server's.
import 'package:wassal/core/economy/domain/economy_refusal.dart';
import 'package:wassal/core/economy/domain/economy_state.dart';
import 'package:wassal/core/economy/domain/op.dart';
import 'package:wassal/core/economy/domain/rules.dart';
import 'package:wassal/features/onboarding/domain/name_rules.dart';

Decision validateSettingsUpdate(
  EconomyState s,
  SettingsUpdateRequest request,
  RuleContext ctx,
) => switch (NameRules.check(request.name)) {
  NameOk(:final normalized) => Validated(
    ctx.op(OpType.settingsUpdate, {'display_name': normalized}),
  ),
  _ => const Declined(EconomyRefusal.invalidName),
};

EconomyState applySettingsUpdate(EconomyState s, Op op) =>
    s.copyWith(displayName: () => op.string('display_name'));

/// Whether [op] is the name [request] would have become.
bool settingsUpdateMatches(Op op, SettingsUpdateRequest request) =>
    op.type == OpType.settingsUpdate &&
    op.payload['display_name'] ==
        NameRules.check(request.name).normalizedOrNull;
