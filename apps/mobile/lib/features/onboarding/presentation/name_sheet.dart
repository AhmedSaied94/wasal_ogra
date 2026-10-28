import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/presentation/name_form.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The Name card's content in a sheet (specs/012-m07-onboarding/contracts/
/// name.md "The re-ask"): Home asks again for a refused name, and M14's
/// Settings for a new one. «تمام» records the name and closes it.
class NameSheet extends StatelessWidget {
  const NameSheet({required this.refused, this.initialName, super.key});

  /// The server refused the last name: the line saying so, above the field.
  final bool refused;

  /// What the field starts with (M14's Settings); else a suggestion.
  final String? initialName;

  static const ctaKey = NameForm.ctaKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s12,
        children: [
          if (refused)
            Text(
              l10n.nameRefusedLine,
              style: DesignExtras.nameRefused.copyWith(
                color: ColorTokens.dangerInk,
              ),
            ),
          NameForm(
            initialName: initialName,
            onSaved: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Opens the [NameSheet] over [context]'s navigator.
Future<void> showNameSheet(
  BuildContext context, {
  required bool refused,
  String? initialName,
}) => showAppSheet<void>(
  context: context,
  title: AppLocalizations.of(context).nameTitle,
  builder: (_) => NameSheet(refused: refused, initialName: initialName),
);
