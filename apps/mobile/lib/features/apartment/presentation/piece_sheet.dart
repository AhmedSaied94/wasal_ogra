// The piece sheet (specs/015-m10-apartment-story, contracts/apartment.md
// "The piece sheet", HANDOFF `Piece`): the styles, سلمى's line, the
// family's mark, the price and the two buttons.
import 'dart:async';

import 'package:content_models/content_models.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/art/apartment_art.dart';
import 'package:wassal/core/content/content_providers.dart';
import 'package:wassal/core/content/domain/story_characters.dart';
import 'package:wassal/core/economy/economy.dart';
import 'package:wassal/core/economy/economy_providers.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/progress/application/player_progress_provider.dart';
import 'package:wassal/core/routing/nav_guard.dart';
import 'package:wassal/core/theme/components/app_icon.dart';
import 'package:wassal/core/theme/components/buttons.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/apartment/application/apartment_providers.dart';
import 'package:wassal/features/apartment/application/piece_purchase.dart';
import 'package:wassal/features/apartment/domain/piece_sheet_model.dart';
import 'package:wassal/core/theme/components/overlays.dart';
import 'package:wassal/features/apartment/presentation/price_chip.dart';
import 'package:wassal/features/apartment/presentation/room_done_dialog.dart';
import 'package:wassal/features/apartment/presentation/room_fallback.dart';
import 'package:wassal/features/home/application/start_next_trip.dart';
import 'package:wassal/features/home/domain/next_trip.dart';
import 'package:wassal/features/home/presentation/start_button.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

const double pieceGap = SpaceTokens.s12;

class PieceSheet extends ConsumerStatefulWidget {
  const PieceSheet({required this.itemId, super.key});

  final String itemId;

  static const closeKey = Key('PieceSheet.close');
  static const buyKey = Key('PieceSheet.buy');
  static const goKey = Key('PieceSheet.go');
  static const previewKey = Key('PieceSheet.preview');

  /// The sheet's grabber (8 + 5) and its bottom padding (14) around the
  /// child, so the child's least height makes the whole 700.
  static const double _sheetChrome = 8 + 5 + 14;

  @override
  ConsumerState<PieceSheet> createState() => _PieceSheetState();
}

class _PieceSheetState extends ConsumerState<PieceSheet> {
  PiecePurchaseResult? _result;
  bool _leaving = false;

  void _leaveLater() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NavGuard.go(context, '/apartment');
    });
  }

  Future<void> _buy(PieceSheetModel model) async {
    final content = ref.read(contentSourceProvider);
    final view = ref.read(economyViewProvider);
    final result = await ref
        .read(piecePurchaseProvider)
        .buy(
          model.item,
          model.selected ?? model.item.variants.first.variantId,
          before: playerProgressOf(view, content),
        );
    if (!mounted) return;
    if (result.outcome is OpApplied) {
      // The rooms view drops the piece in and سلمى comments, once the sheet
      // is gone.
      ref
          .read(boughtPieceProvider.notifier)
          .bought(
            model.item.itemId,
            model.selected ?? model.item.variants.first.variantId,
          );
      if (result.roomCompleted) {
        // RoomDone opens before the sheet leaves, so the room it draws is
        // the completed one (contracts/apartment.md "RoomDone").
        final router = GoRouter.of(context);
        // The bought piece's own room, not the current chapter's: completing
        // it can move the story on to a room of its own.
        final roomId = model.item.roomId;
        final done = ref.read(roomModelOfProvider(roomId));
        if (done == null) {
          Navigator.of(context).pop(result);
          return;
        }
        // The chapter's goal scene is pack data: the same before and after
        // the purchase reaches the progress.
        final goalScene = done.goalScene;
        final watch = await showAppDialog<bool>(
          context: context,
          // Read when the dialog builds, a frame on: the room's model then
          // holds the piece just bought.
          builder: (_) => RoomDoneDialog(
            model: ref.read(roomModelOfProvider(roomId)) ?? done,
            chapterCompleted: result.chapterCompleted,
          ),
        );
        if (!mounted) return;
        // «شوف المشهد» replaces this sheet with the scene, which goes back to
        // the apartment: popping the sheet after pushing the scene would pop
        // the scene.
        if (watch ?? false) {
          if (goalScene case final scene?) {
            unawaited(
              router.pushReplacement(
                Uri(
                  path: '/story/scene/${scene.sceneId}',
                  queryParameters: {'then': '/apartment'},
                ).toString(),
              ),
            );
            return;
          }
        }
      }
      Navigator.of(context).pop(result);
      return;
    }
    setState(() => _result = result);
  }

  void _goTrip() {
    final content = ref.read(contentSourceProvider);
    final progress = ref.read(playerProgressProvider);
    final next = nextTrip(content, progress, lastFinishedTripId: null);
    if (next == null) return;
    startNextTrip(context, ref, tripId: next.tripId, from: StartFrom.apartment);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = ref.watch(numberFormatterProvider);
    final model = ref.watch(pieceSheetModelProvider(widget.itemId));
    if (model == null || model.owned) {
      // Owned, in a locked room, or not in the pack: back to the tab once.
      _leaveLater();
      return const SizedBox.shrink();
    }
    // A refused purchase says why, in the status line's place.
    final refusal = switch (_result?.outcome) {
      OpRefused(:final code) =>
        code == EconomyRefusal.insufficientFunds
            ? l10n.pieceShort(numbers.integer(model.shortfall))
            : l10n.buyVehicleDone,
      _ => null,
    };
    return Padding(
      // The sheet's 14 and these 2 are the board's 16.
      padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s2),
      child: ConstrainedBox(
        // The board's sheet is 700 high whatever it lists.
        constraints: const BoxConstraints(
          minHeight: DesignExtras.pieceSheetHeight - PieceSheet._sheetChrome,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: SpaceTokens.s10),
              _Header(model: model, closeLabel: l10n.closeLabel),
              const SizedBox(height: SpaceTokens.s14),
              _Preview(model: model),
              const SizedBox(height: pieceGap),
              _Styles(model: model),
              if (model.salmaLine case final line?) ...[
                const SizedBox(height: pieceGap),
                _Salma(line: line),
              ],
              const SizedBox(height: pieceGap),
              _Price(model: model, numbers: numbers),
              if (model.askerToMiss case final asker?) ...[
                const SizedBox(height: pieceGap),
                Text(
                  l10n.pieceMissesRequest(l10n.sceneSpeaker(asker)),
                  textAlign: TextAlign.center,
                  style: TypeTokens.caption
                      .weight(700)
                      .copyWith(color: ColorTokens.dangerInk),
                ),
              ],
              if (model.affordable) ...[
                if (refusal != null) ...[
                  const SizedBox(height: pieceGap),
                  Text(
                    refusal,
                    textAlign: TextAlign.center,
                    style: DesignExtras.piecePriceHave.copyWith(
                      color: ColorTokens.dangerInk,
                    ),
                  ),
                ],
                // The warning, when there is one, sits 8 above the button
                // (`PieceAffordable` 33, 34).
                SizedBox(
                  height: model.askerToMiss != null || refusal != null
                      ? SpaceTokens.s8
                      : pieceGap,
                ),
                AppButton.primary(
                  key: PieceSheet.buyKey,
                  label: l10n.pieceBuy,
                  trailing: PriceChip(
                    label: l10n.pieceBuyCost(numbers.integer(model.price)),
                  ),
                  semanticLabel: l10n.pieceBuyA11y(
                    model.item.name.arEg,
                    model.variants
                            .where((v) => v.variantId == model.selected)
                            .firstOrNull
                            ?.name
                            .arEg ??
                        model.variants.first.name.arEg,
                    numbers.integer(model.price),
                  ),
                  height: LayoutTokens.ctaH,
                  radius: LayoutTokens.ctaRadius,
                  onTap: () => _buy(model),
                ),
              ] else ...[
                const SizedBox(height: pieceGap),
                Text(
                  refusal ?? l10n.pieceShort(numbers.integer(model.shortfall)),
                  textAlign: TextAlign.center,
                  style: DesignExtras.piecePriceHave.copyWith(
                    color: ColorTokens.dangerInk,
                  ),
                ),
                const SizedBox(height: SpaceTokens.s4),
                AppButton.primary(
                  key: PieceSheet.goKey,
                  label: l10n.pieceGoTrip,
                  // A trip costs a liter, as Home's «يلا نطلع!».
                  trailing: CostChip(
                    amount: l10n.homeFuelCost(numbers.integer(litersPerStart)),
                    large: true,
                  ),
                  height: LayoutTokens.ctaH,
                  radius: LayoutTokens.ctaRadius,
                  onTap: _goTrip,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The room over the piece's name, and ✕ at the end (`Piece` 8–11).
class _Header extends StatelessWidget {
  const _Header({required this.model, required this.closeLabel});

  final PieceSheetModel model;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => Row(
    spacing: SpaceTokens.s10,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.room.name.arEg,
              style: DesignExtras.pieceRoom.copyWith(
                color: ColorTokens.inkMuted,
              ),
            ),
            Semantics(
              header: true,
              child: Text(
                model.item.name.arEg,
                maxLines: 2,
                style: DesignExtras.requestsTitle.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
            ),
          ],
        ),
      ),
      IconCircleButton(
        key: PieceSheet.closeKey,
        icon: 'close',
        semanticLabel: closeLabel,
        inSheet: true,
        onTap: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

class _Preview extends StatelessWidget {
  const _Preview({required this.model});

  final PieceSheetModel model;

  @override
  Widget build(BuildContext context) {
    final variant = model.variants
        .where((v) => v.variantId == model.selected)
        .firstOrNull;
    final art = variant == null ? null : ApartmentArt.piece(variant.art);
    return Container(
      key: PieceSheet.previewKey,
      height: DesignExtras.pieceArtHeight,
      decoration: BoxDecoration(
        color: DesignExtras.sceneRoomGround,
        borderRadius: BorderRadius.circular(RadiusTokens.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: art == null
                ? const PieceFallback()
                : SvgPicture.asset(
                    art,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          ),
          if (variant != null)
            PositionedDirectional(
              top: DesignExtras.pieceStyleChipInset,
              start: DesignExtras.pieceStyleChipInset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ColorTokens.paper,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpaceTokens.s12,
                    vertical: SpaceTokens.s4,
                  ),
                  child: Text(
                    variant.name.arEg,
                    style: DesignExtras.pieceStyleChip.copyWith(
                      color: ColorTokens.ink,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Styles extends ConsumerWidget {
  const _Styles({required this.model});

  final PieceSheetModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Row(
      spacing: DesignExtras.pieceTileGap,
      children: [
        for (final variant in model.variants)
          Expanded(
            child: _RequestMarked(
              mark: model.requestMarks[variant.variantId] == null
                  ? null
                  : l10n.pieceRequestMark(
                      l10n.sceneSpeaker(model.requestMarks[variant.variantId]!),
                    ),
              child: Pressable(
                expand: true,
                onTap: () => ref
                    .read(pieceStyleMemoryProvider.notifier)
                    .choose(model.item.itemId, variant.variantId),
                lip: model.selected == variant.variantId
                    ? LipTokens.cardSmall
                    : null,
                borderRadius: BorderRadius.circular(RadiusTokens.bubble),
                semanticLabel: model.requestMarks[variant.variantId] == null
                    ? variant.name.arEg
                    : l10n.pieceRequestA11y(
                        variant.name.arEg,
                        l10n.pieceRequestMark(
                          l10n.sceneSpeaker(
                            model.requestMarks[variant.variantId]!,
                          ),
                        ),
                      ),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: DesignExtras.pieceTileHeight,
                  ),
                  decoration: BoxDecoration(
                    color: model.selected == variant.variantId
                        ? ColorTokens.paper
                        : ColorTokens.ground,
                    borderRadius: BorderRadius.circular(RadiusTokens.bubble),
                    border: model.selected == variant.variantId
                        ? RingTokens.selected.border
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: DesignExtras.pieceTileArtTop),
                      SizedBox(
                        height: DesignExtras.pieceTileArtHeight,
                        width: DesignExtras.pieceTileArtWidth,
                        child: ApartmentArt.piece(variant.art) == null
                            ? const PieceFallback()
                            : SvgPicture.asset(
                                ApartmentArt.piece(variant.art)!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                      ),
                      const SizedBox(height: SpaceTokens.s6),
                      Text(
                        variant.name.arEg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (model.selected == variant.variantId
                                    ? DesignExtras.pieceTileChosen
                                    : DesignExtras.pieceTile)
                                .copyWith(
                                  color: model.selected == variant.variantId
                                      ? ColorTokens.primary
                                      : ColorTokens.ink,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A style tile and, when a family request names it, the sun mark hanging off
/// its bottom edge (`PieceAffordable` 16 to 18). The mark is a picture of the
/// request: the tile's own label reads it aloud.
class _RequestMarked extends StatelessWidget {
  const _RequestMarked({required this.mark, required this.child});

  final String? mark;
  final Widget child;

  /// How far the mark hangs below the tile, and its sides' inset.
  static const double hang = 10;

  @override
  Widget build(BuildContext context) {
    final text = mark;
    if (text == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        PositionedDirectional(
          start: SpaceTokens.s4,
          end: SpaceTokens.s4,
          bottom: -hang,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: SpaceTokens.s8,
                  vertical: SpaceTokens.s2,
                ),
                decoration: BoxDecoration(
                  color: ColorTokens.sun,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                // A narrow tile: the mark wraps to two lines, as drawn.
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: DesignExtras.chipLabel.copyWith(
                    color: ColorTokens.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Salma extends StatelessWidget {
  const _Salma({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(
        minHeight: DesignExtras.pieceSalmaHeight,
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: SpaceTokens.s12,
        vertical: SpaceTokens.s8,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.sunSoft,
        borderRadius: BorderRadius.circular(RadiusTokens.bubble),
      ),
      child: Row(
        spacing: SpaceTokens.s10,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: ColorTokens.paper,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: SizedBox.square(
                dimension: DesignExtras.pieceSalmaFace,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: CharacterAvatar(
                    storyCharacterArt(StoryCharacter.salma),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              l10n.pieceSalma(line),
              style: DesignExtras.pieceSalma.copyWith(color: ColorTokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The price over what the player has, in a ringed card (`Piece` 26–31).
class _Price extends StatelessWidget {
  const _Price({required this.model, required this.numbers});

  final PieceSheetModel model;
  final NumberFormatter numbers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = DesignExtras.piecePriceLabel.copyWith(color: ColorTokens.ink);
    return Container(
      constraints: const BoxConstraints(
        minHeight: DesignExtras.piecePriceHeight,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        SpaceTokens.s14,
        SpaceTokens.s6,
        SpaceTokens.s14,
        SpaceTokens.s14,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.paper,
        borderRadius: BorderRadius.circular(RadiusTokens.bubble),
        border: Border.all(color: ColorTokens.track, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            // A wider text scale wraps the caption and grows the row.
            constraints: const BoxConstraints(
              minHeight: DesignExtras.piecePriceRowHeight,
            ),
            child: Row(
              spacing: SpaceTokens.s8,
              children: [
                Expanded(child: Text(l10n.pieceSamePrice, style: label)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: SpaceTokens.s2,
                  children: [
                    const AppIcon('coin', size: 22),
                    Text(
                      numbers.integer(model.price),
                      style: DesignExtras.piecePriceAmount.copyWith(
                        color: ColorTokens.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SpaceTokens.s6),
          const SizedBox(
            height: DesignExtras.piecePriceLine,
            width: double.infinity,
            child: ColoredBox(color: ColorTokens.track),
          ),
          const SizedBox(height: SpaceTokens.s6),
          Row(
            children: [
              Text(l10n.pieceBalance, style: label),
              const Spacer(),
              Text(
                l10n.aptRoomsPrice(numbers.integer(model.jenehat)),
                style: DesignExtras.piecePriceHave.copyWith(
                  color: ColorTokens.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
