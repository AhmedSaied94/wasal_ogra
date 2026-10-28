import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/domain/name_rules.dart';
import 'package:wassal/features/onboarding/domain/name_suggestions.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The Name card's form (specs/012-m07-onboarding/contracts/name.md), on
/// the card and in the sheet: the field with a suggestion already in it,
/// the dice, the helper line and «تمام», which records the name. Nothing
/// waits for the server.
class NameForm extends ConsumerStatefulWidget {
  const NameForm({required this.onSaved, this.initialName, super.key});

  /// After the name was recorded.
  final VoidCallback onSaved;

  /// What the field starts with (M14's Settings); else a suggestion.
  final String? initialName;

  static const ctaKey = Key('NameScreen.cta');
  static const diceKey = Key('NameScreen.dice');

  @override
  ConsumerState<NameForm> createState() => _NameFormState();
}

class _NameFormState extends ConsumerState<NameForm>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late final NameSuggestions _suggestions;
  bool _started = false;
  bool _saving = false;

  /// The dice's swap: the field fades back in from [_swapFrom].
  late final _swap = AnimationController(
    vsync: this,
    duration: DesignExtras.nameDiceSwap,
    value: 1,
  );
  static const double _swapFrom = 0.3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _suggestions = NameSuggestions(
      namePoolOf(AppLocalizations.of(context).namePool),
      seed: ref.read(nameSeedProvider),
    );
    _controller.text = widget.initialName ?? _suggestions.first;
  }

  @override
  void dispose() {
    _swap.dispose();
    _controller.dispose();
    super.dispose();
  }

  NameCheck get _check => NameRules.check(_controller.text);

  void _another() {
    _controller.text = _suggestions.another(_controller.text);
    if (!MediaQuery.disableAnimationsOf(context)) {
      unawaited(_swap.forward(from: 0));
    }
    setState(() {});
  }

  Future<void> _save() async {
    final name = _check.normalizedOrNull;
    if (name == null || _saving) return;
    setState(() => _saving = true);
    final economy = ref.read(economyProvider).requireValue;
    final outcome = await economy.setDisplayName(economy.newRequestId(), name);
    if (!mounted) return;
    if (outcome is! OpApplied) {
      // Nothing was written: the player may press again.
      setState(() => _saving = false);
      return;
    }
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s14,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: SpaceTokens.s6,
          children: [
            // The field carries the label for a screen reader.
            ExcludeSemantics(
              child: Text(
                l10n.nameFieldLabel,
                style: DesignExtras.nameLabel.copyWith(color: ColorTokens.ink),
              ),
            ),
            Row(
              spacing: SpaceTokens.s8,
              children: [
                Expanded(
                  child: FadeTransition(
                    opacity: Tween(begin: _swapFrom, end: 1.0).animate(_swap),
                    child: AppTextField(
                      controller: _controller,
                      semanticLabel: l10n.nameFieldLabel,
                      maxLength: nameMaxLength,
                      height: DesignExtras.nameFieldHeight,
                      fill: ColorTokens.ground,
                      textStyle: DesignExtras.nameFieldText,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => unawaited(_save()),
                    ),
                  ),
                ),
                _Dice(
                  key: NameForm.diceKey,
                  label: l10n.nameSuggestAnother,
                  onTap: _another,
                ),
              ],
            ),
            Text(
              l10n.nameHelper,
              style: DesignExtras.nameHelper.copyWith(
                color: ColorTokens.inkMuted,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: SpaceTokens.s4),
          child: AppButton.primary(
            key: NameForm.ctaKey,
            label: l10n.nameCta,
            size: AppButtonSize.l,
            height: DesignExtras.nameCtaHeight,
            labelStyle: DesignExtras.nameCtaLabel,
            enabled: _check.isOk,
            loading: _saving,
            onTap: () => unawaited(_save()),
          ),
        ),
      ],
    );
  }
}

/// `Name` block 1f: the dice, 54 square on `sun.soft`.
class _Dice extends StatelessWidget {
  const _Dice({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  static const double _glyph = 24;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.m);
    return Pressable(
      onTap: onTap,
      lip: DesignExtras.nameDiceLip,
      borderRadius: radius,
      semanticLabel: label,
      child: Container(
        width: DesignExtras.nameDice,
        height: DesignExtras.nameDice,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ColorTokens.sunSoft,
          borderRadius: radius,
        ),
        child: const AppIcon('dice', size: _glyph, color: ColorTokens.ink),
      ),
    );
  }
}
