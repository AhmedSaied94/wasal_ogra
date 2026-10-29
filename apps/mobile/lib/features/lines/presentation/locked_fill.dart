// The progression-locked look on tiles and cells (HANDOFF §9.1 #6;
// specs/014-m09-lines-vehicles, research R11): `locked.bg`, the 2 pt
// locked ring inside, `ink.2` text and a lock, never faded. A line card
// gets the same from `AppCard(locked: true)`.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

BoxDecoration lockedFill(BorderRadius radius) => BoxDecoration(
  color: ColorTokens.lockedBg,
  borderRadius: radius,
  border: RingTokens.locked.border,
);

/// The lock on a locked tile or cell, `ink.muted` as the boards of
/// 2026-10-29 draw it.
class LockGlyph extends StatelessWidget {
  const LockGlyph({this.size = 14, super.key});

  final double size;

  @override
  Widget build(BuildContext context) =>
      AppIcon('lock', size: size, color: ColorTokens.inkMuted);
}
