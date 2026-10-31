// The room's drawing (specs/015-m10-apartment-story, contracts/apartment.md
// "The rooms view", HANDOFF `AptRooms` block 4): the room, the owned pieces
// in their styles, a dashed outline for each missing slot and its chip, in
// the 358 x 300 design space. After a purchase the new piece drops in and
// سلمى's bubble hangs under it (`AptRoomsBought`).
import 'package:content_models/content_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/apartment_art.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/domain/room_model.dart';
import 'package:wassal/features/apartment/presentation/room_fallback.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The room's design space, `AptRooms` block 4.
const Size roomDesign = Size(358, 300);

/// What follows a purchase on the drawing: the piece that drops in and what
/// سلمى says under it.
typedef RoomBought = ({Item item, String variantId, String line});

class RoomScene extends ConsumerWidget {
  const RoomScene({required this.model, this.onTap, this.bought, super.key});

  final RoomModel model;

  /// A missing piece's chip was tapped.
  final void Function(Item item)? onTap;

  /// The piece just bought, if it is in this room.
  final RoomBought? bought;

  /// The chip's height (HANDOFF §3, SC-006: 44 in the design space).
  static const double chipHeight = 44;

  /// The bubble's distance from the room's sides, and its height.
  static const double bubbleInset = 24;
  static const double bubbleHeight = 54;

  /// How far the bubble's top sits above the piece's bottom.
  static const double bubbleOverlap = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbers = ref.watch(numberFormatterProvider);
    final l10n = AppLocalizations.of(context);
    final room = model.room;
    final art = room.art == null ? null : ApartmentArt.room(room.art!);
    return AspectRatio(
      aspectRatio: roomDesign.width / roomDesign.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RadiusTokens.scene),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox.fromSize(
            size: roomDesign,
            child: Stack(
              children: [
                Positioned.fill(
                  child: art == null
                      ? const RoomFallback()
                      : SvgPicture.asset(art, fit: BoxFit.cover),
                ),
                for (final cell in model.pieces)
                  ..._layers(l10n, numbers, cell),
                if (bought case final bought?) _bubble(l10n, bought),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _layers(
    AppLocalizations l10n,
    NumberFormatter numbers,
    PieceCell cell,
  ) {
    final slot = cell.item.slot;
    Widget inSlot(Widget child) => Positioned(
      left: slot.x.toDouble(),
      top: slot.y.toDouble(),
      width: slot.w.toDouble(),
      height: slot.h.toDouble(),
      child: child,
    );
    return switch (cell) {
      OwnedCell(:final item, :final variantId) => [
        inSlot(
          _DropIn(
            key: ValueKey('RoomScene.piece.${item.itemId}'),
            animate: bought?.item.itemId == item.itemId,
            child: _PieceArt(
              item: item,
              variantId: variantId ?? item.variants.firstOrNull?.variantId,
            ),
          ),
        ),
      ],
      NextTargetCell(:final item, :final price) ||
      MissingCell(:final item, :final price) => [
        inSlot(const CustomPaint(painter: _DashedSlot())),
        Positioned(
          left: (slot.x + slot.w / 2 - 60).clamp(8.0, roomDesign.width - 128),
          top: (slot.y + slot.h / 2 - chipHeight / 2).clamp(
            8.0,
            roomDesign.height - chipHeight - 8,
          ),
          child: _Chip(
            label: l10n.aptRoomsChip(item.name.arEg, numbers.integer(price)),
            semanticLabel: l10n.aptRoomsChipA11y(
              item.name.arEg,
              numbers.integer(price),
            ),
            onTap: onTap == null ? null : () => onTap!(item),
          ),
        ),
      ],
    };
  }

  /// سلمى's bubble: anchored to the piece, its tail pointing up at it, 24 in
  /// from the room's sides and clear of the room's bottom.
  Widget _bubble(AppLocalizations l10n, RoomBought bought) {
    final slot = bought.item.slot;
    final top = (slot.y + slot.h - bubbleOverlap).clamp(
      8.0,
      roomDesign.height - bubbleInset - bubbleHeight,
    );
    final width = roomDesign.width - 2 * bubbleInset;
    final tip = (slot.x + slot.w / 2 - bubbleInset).clamp(
      DesignExtras.bubbleTail * 2,
      width - DesignExtras.bubbleTail * 2,
    );
    return Positioned(
      left: bubbleInset,
      top: top,
      width: width,
      child: _SalmaBubble(
        key: const ValueKey('RoomScene.bubble'),
        line: l10n.aptBoughtBubble(bought.line),
        semanticLabel: l10n.aptBoughtBubbleA11y(bought.line),
        tipX: tip,
      ),
    );
  }
}

/// The piece settling into its slot: from 24 above and clear to its place
/// over `dialogIn`; under reduced motion it only fades.
class _DropIn extends StatelessWidget {
  const _DropIn({required this.animate, required this.child, super.key});

  final bool animate;
  final Widget child;

  /// How far above its slot the piece starts.
  static const double fall = 24;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionTokens.dialogIn,
      curve: MotionTokens.dialogInCurve,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: reduced
            ? child
            : Transform.translate(
                offset: Offset(0, -fall * (1 - t)),
                child: child,
              ),
      ),
    );
  }
}

class _PieceArt extends StatelessWidget {
  const _PieceArt({required this.item, required this.variantId});

  final Item item;
  final String? variantId;

  @override
  Widget build(BuildContext context) {
    final variant = item.variants
        .where((v) => v.variantId == variantId)
        .firstOrNull;
    final art = variant == null ? null : ApartmentArt.piece(variant.art);
    return art == null ? const PieceFallback() : SvgPicture.asset(art);
  }
}

/// The chip: a blue «+» and «{item} · {price}» (`AptRooms` block 4), 44 high.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.semanticLabel, this.onTap});

  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(RadiusTokens.pill);
    return Pressable(
      onTap: onTap,
      borderRadius: radius,
      lip: LipTokens.cardSmall,
      semanticLabel: semanticLabel,
      child: Container(
        height: RoomScene.chipHeight,
        padding: const EdgeInsetsDirectional.fromSTEB(
          SpaceTokens.s6,
          0,
          SpaceTokens.s12,
          0,
        ),
        decoration: BoxDecoration(
          color: ColorTokens.paper,
          borderRadius: radius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: SpaceTokens.s6,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: ColorTokens.primary,
                shape: BoxShape.circle,
              ),
              child: const AppIcon('plus', size: 14, color: ColorTokens.paper),
            ),
            Text(
              label,
              style: DesignExtras.compactLabel.copyWith(color: ColorTokens.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// سلمى's line over the room: her face 46 at the start, the line beside it,
/// and a tail up to the piece (`AptRoomsBought`).
class _SalmaBubble extends StatelessWidget {
  const _SalmaBubble({
    required this.line,
    required this.semanticLabel,
    required this.tipX,
    super.key,
  });

  final String line;
  final String semanticLabel;

  /// Where the tail's centre falls, from the bubble's own start side.
  final double tipX;

  @override
  Widget build(BuildContext context) {
    const tail = DesignExtras.bubbleTail;
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // `tipX` is measured from the room's left; the bubble's box is the
          // same in either direction.
          Positioned(
            top: -tail / 2,
            left: tipX - tail / 2,
            child: const SpeechBubbleTail(variant: SpeechBubbleVariant.normal),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: ColorTokens.paper,
              borderRadius: BorderRadius.circular(RadiusTokens.bubble),
              boxShadow: const [LipTokens.bubble],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: RoomScene.bubbleHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.all(SpaceTokens.s4),
                child: Row(
                  spacing: SpaceTokens.s10,
                  children: [
                    ClipOval(
                      child: SizedBox.square(
                        dimension: 46,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: CharacterAvatar(
                            storyCharacterArt(StoryCharacter.salma),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: TypeTokens.quote
                            .weight(700)
                            .copyWith(color: ColorTokens.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedSlot extends CustomPainter {
  const _DashedSlot();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ColorTokens.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final rect = Offset.zero & size;
    const radius = Radius.circular(RadiusTokens.s);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect.deflate(2), radius));
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, at + 8), paint);
        at += 14;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
